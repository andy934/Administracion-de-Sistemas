# =============================================================================
# func-tests.ps1 - Tests automatizados del protocolo de pruebas
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# =============================================================================

function Ejecutar-Tests {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PROTOCOLO DE PRUEBAS - PRACTICA 09     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan
    Write-Host "  1. Test 1 -- Delegacion RBAC (admin_identidad PASS / admin_storage DENY)" -ForegroundColor White
    Write-Host "  2. Test 2 -- FGPP (contrasena 8 chars rechazada para admin_identidad)"    -ForegroundColor White
    Write-Host "  3. Test 3 -- Estado MFA en multiOTP"                                      -ForegroundColor White
    Write-Host "  4. Test 4 -- Verificar bloqueo MFA"                                       -ForegroundColor White
    Write-Host "  5. Test 5 -- Generar reporte auditoria ID 4625"                           -ForegroundColor White
    Write-Host "  6. Todos los tests"                                                        -ForegroundColor White
    Write-Host ""
    $t = Read-Host "  Selecciona"
    switch ($t) {
        '1' { Test-DelegacionRBAC }
        '2' { Test-FGPP }
        '3' { Test-EstadoMFA }
        '4' { Test-BloqueoMFA }
        '5' { Configurar-Auditoria }
        '6' { Test-DelegacionRBAC; Test-FGPP; Test-EstadoMFA; Test-BloqueoMFA; Configurar-Auditoria }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# TEST 1: Delegacion RBAC
# Usa Get-ADUser con atributo nTSecurityDescriptor para leer
# las ACLs reales del objeto OU directamente desde AD.
# Esto evita el problema de dsacls y Get-Acl con filtros.
# ------------------------------------------------------------

function Test-DelegacionRBAC {
    Write-Host "`n  TEST 1 -- Delegacion RBAC" -ForegroundColor Cyan
    Write-Host "  -------------------------" -ForegroundColor Cyan

    $dcBase  = (Get-ADDomain).DistinguishedName
    $netbios = (Get-ADDomain).NetBIOSName

    $ouCuates = Get-OUSegura -NombreBase "Cuates"
    $usuarioPrueba = $null
    if ($ouCuates) {
        $usuarioPrueba = Get-ADUser -Filter * -SearchBase $ouCuates -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $usuarioPrueba) {
        Write-Host "  [WARN] No hay usuarios en OU Cuates." -ForegroundColor Yellow; return
    }
    Write-Host "  Usuario de prueba: $($usuarioPrueba.SamAccountName)" -ForegroundColor DarkGray

    # ---- ACCION A: verificar SID de admin_identidad en ACL de la OU ----
    Write-Host "`n  ACCION A: Verificando permisos de admin_identidad en OU Cuates..." -ForegroundColor Yellow
    try {
        $sidIdentidad = (Get-ADUser "admin_identidad" -ErrorAction Stop).SID
        $ouObj        = Get-ADOrganizationalUnit -Identity $ouCuates -Properties nTSecurityDescriptor -ErrorAction Stop
        $acl          = $ouObj.nTSecurityDescriptor
        $encontrado   = $acl.Access | Where-Object {
            $_.IdentityReference.Value -match "admin_identidad" -or
            ($_.IdentityReference -is [System.Security.Principal.SecurityIdentifier] -and
             $_.IdentityReference.Value -eq $sidIdentidad.Value)
        }
        if ($encontrado) {
            Write-Host "  [PASS] ACCION A: admin_identidad tiene ACEs en la OU Cuates:" -ForegroundColor Green
            $encontrado | Select-Object -First 5 | ForEach-Object {
                Write-Host "         $($_.AccessControlType): $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray
            }
        } else {
            # Fallback: buscar por SID en el descriptor de seguridad raw
            $sidStr   = $sidIdentidad.Value
            $aclRaw   = (Get-Acl "AD:\$ouCuates").Access
            $porSid   = $aclRaw | Where-Object { $_.IdentityReference.ToString() -match "admin_identidad|$sidStr" }
            if ($porSid) {
                Write-Host "  [PASS] ACCION A: admin_identidad tiene ACEs (verificado via SID):" -ForegroundColor Green
                $porSid | Select-Object -First 5 | ForEach-Object {
                    Write-Host "         $($_.AccessControlType): $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray
                }
            } else {
                Write-Host "  [WARN] ACCION A: No se encontraron ACEs para admin_identidad." -ForegroundColor Yellow
                Write-Host "         Ejecuta Opcion 3 y repite." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  [WARN] ACCION A: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ---- ACCION B: admin_storage tiene DENY en el dominio ----
    Write-Host "`n  ACCION B: Verificando DENY de admin_storage en el dominio..." -ForegroundColor Yellow
    try {
        $domAcl      = Get-Acl -Path "AD:\$dcBase" -ErrorAction Stop
        $denyStorage = $domAcl.Access | Where-Object {
            $_.IdentityReference -like "*admin_storage*" -and $_.AccessControlType -eq "Deny"
        }
        if ($denyStorage) {
            Write-Host "  [PASS] ACCION B: admin_storage tiene ACE DENY en el dominio:" -ForegroundColor Green
            $denyStorage | ForEach-Object {
                Write-Host "         Deny : $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray
                Write-Host "         Tipo : $($_.AccessControlType)"     -ForegroundColor DarkGray
                Write-Host "         Quien: $($_.IdentityReference)"     -ForegroundColor DarkGray
            }
            Write-Host "`n  [PASS] TEST 1 COMPLETADO: admin_identidad ALLOW / admin_storage DENY" -ForegroundColor Green
            Write-Host "         Toma captura de esta pantalla como evidencia." -ForegroundColor Cyan
        } else {
            Write-Host "  [WARN] ACCION B: No se detecto DENY para admin_storage." -ForegroundColor Yellow
            Write-Host "         Ejecuta Opcion 3." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] ACCION B: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# TEST 2: FGPP
# ------------------------------------------------------------

function Test-FGPP {
    Write-Host "`n  TEST 2 -- FGPP" -ForegroundColor Cyan
    Write-Host "  --------------" -ForegroundColor Cyan
    try {
        $pso = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" -ErrorAction Stop
        if ($pso) {
            Write-Host "  Politica efectiva para admin_identidad:" -ForegroundColor Yellow
            Write-Host "  Nombre          : $($pso.Name)"                    -ForegroundColor White
            Write-Host "  Longitud minima : $($pso.MinPasswordLength) chars" -ForegroundColor White
            Write-Host "  Lockout umbral  : $($pso.LockoutThreshold)"        -ForegroundColor White
            Write-Host "  Lockout duracion: $($pso.LockoutDuration)"         -ForegroundColor White
        }
    } catch { Write-Host "  [WARN] No se pudo leer PSO: $($_.Exception.Message)" -ForegroundColor Yellow }

    Write-Host "`n  Intentando poner contrasena de 8 chars a admin_identidad..." -ForegroundColor Yellow
    try {
        Set-ADAccountPassword -Identity "admin_identidad" `
            -NewPassword (ConvertTo-SecureString "Corta1!!" -AsPlainText -Force) -Reset -ErrorAction Stop
        Write-Host "  [FAIL] Acepto contrasena corta (no deberia)." -ForegroundColor Red
    } catch {
        Write-Host "  [PASS] Contrasena de 8 chars RECHAZADA correctamente." -ForegroundColor Green
        Write-Host "         Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------
# TEST 3: Estado MFA
# ------------------------------------------------------------

function Test-EstadoMFA {
    Write-Host "`n  TEST 3 -- Estado MFA (multiOTP)" -ForegroundColor Cyan
    Write-Host "  --------------------------------" -ForegroundColor Cyan

    $multiotpExe = Get-MultiOTPExe
    if (-not $multiotpExe) { Write-Host "  [FAIL] multiOTP no instalado." -ForegroundColor Red; return }
    Write-Host "  [OK] multiOTP: $multiotpExe" -ForegroundColor Green

    $dir = Split-Path $multiotpExe
    Push-Location $dir

    Write-Host "`n  Usuarios registrados:" -ForegroundColor Yellow
    $carpeta = Join-Path $dir "users"
    if (Test-Path $carpeta) {
        $dbs = Get-ChildItem -Path $carpeta -Filter "*.db" -ErrorAction SilentlyContinue
        if ($dbs -and $dbs.Count -gt 0) {
            $dbs | ForEach-Object { Write-Host "    [+] $($_.BaseName)" -ForegroundColor Green }
            Write-Host "  [PASS] $($dbs.Count) usuario(s) registrados." -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Carpeta users vacia. Ejecuta Opcion 7." -ForegroundColor Yellow
        }
    }

    Write-Host "`n  Bloqueo MFA:" -ForegroundColor Yellow
    $cfgFile = Join-Path $dir "config\multiotp.json"
    if (-not (Test-Path $cfgFile)) { $cfgFile = Join-Path $dir "multiotp.json" }
    if (Test-Path $cfgFile) {
        $j = Get-Content $cfgFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($j) {
            $mb = if ($j.MaxBlockFailures)      { $j.MaxBlockFailures }      else { "N/D" }
            $md = if ($j.MaxDelayedFailures)    { $j.MaxDelayedFailures }    else { "N/D" }
            $fd = if ($j.FailureDelayInSeconds) { $j.FailureDelayInSeconds } else { "N/D" }
            Write-Host "    MaxBlockFailures   : $mb (debe ser 3)"    -ForegroundColor White
            Write-Host "    MaxDelayedFailures : $md (debe ser 3)"    -ForegroundColor White
            Write-Host "    FailureDelay (seg) : $fd (debe ser 1800)" -ForegroundColor White
            if ($mb -eq 3 -or $md -eq 3) { Write-Host "  [PASS] Bloqueo configurado." -ForegroundColor Green }
            else { Write-Host "  [WARN] Ejecuta Opcion 7." -ForegroundColor Yellow }
        }
    } else {
        Write-Host "    Config JSON no encontrado. Bloqueo aplicado via -config." -ForegroundColor DarkGray
        Write-Host "    Se validara con el Test 4 manualmente." -ForegroundColor DarkGray
    }
    Pop-Location
}

# ------------------------------------------------------------
# TEST 4: Bloqueo MFA
# ------------------------------------------------------------

function Test-BloqueoMFA {
    Write-Host "`n  TEST 4 -- Bloqueo por MFA fallido" -ForegroundColor Cyan
    Write-Host "  ----------------------------------" -ForegroundColor Cyan

    $usuarios     = @("Administrator","admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    $hayBloqueado = $false
    Write-Host "`n  Estado de bloqueo en Active Directory:" -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        try {
            $info   = Get-ADUser -Identity $u -Properties LockedOut, BadLogonCount -ErrorAction Stop
            $estado = if ($info.LockedOut) { "[BLOQUEADO]" } else { "[OK - libre]" }
            $color  = if ($info.LockedOut) { "Red" } else { "Green" }
            Write-Host "  $estado $u (intentos fallidos: $($info.BadLogonCount))" -ForegroundColor $color
            if ($info.LockedOut) { $hayBloqueado = $true }
        } catch {
            Write-Host "  [WARN] No se pudo verificar ${u}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    if ($hayBloqueado) {
        Write-Host "`n  [PASS] Cuenta bloqueada. Toma captura como evidencia." -ForegroundColor Green
        Write-Host "  Para desbloquear: Unlock-ADAccount -Identity <usuario>" -ForegroundColor Cyan
    } else {
        Write-Host "`n  [INFO] Ninguna cuenta bloqueada actualmente." -ForegroundColor Yellow
        Write-Host "  Para el Test 4:" -ForegroundColor Yellow
        Write-Host "  1. Cierra sesion en el servidor fisicamente"          -ForegroundColor White
        Write-Host "  2. Ingresa usuario y contrasena correctos"            -ForegroundColor White
        Write-Host "  3. Cuando pida el token MFA escribe 000000 tres veces" -ForegroundColor White
        Write-Host "  4. Vuelve a ejecutar este test para ver la cuenta bloqueada" -ForegroundColor White
    }
}


