# ============================================================
#  funciones_p9.ps1 -- Libreria de funciones Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA TOTP
#  Version final - todos los tests automatizados
# ============================================================

# ------------------------------------------------------------
# UTILIDAD: Detectar nombre real de OUs creadas en P08
# ------------------------------------------------------------
function Get-OUSegura {
    param([string]$NombreBase)
    $dcBase    = (Get-ADDomain).DistinguishedName
    $variantes = @($NombreBase, ($NombreBase -replace ' ',''))
    foreach ($v in $variantes) {
        try {
            Get-ADOrganizationalUnit -Identity "OU=$v,$dcBase" -ErrorAction Stop | Out-Null
            return "OU=$v,$dcBase"
        } catch {}
    }
    Write-Host "  [AVISO] OU '$NombreBase' no existe. Creandola..." -ForegroundColor Yellow
    try {
        New-ADOrganizationalUnit -Name $NombreBase -Path $dcBase -ErrorAction Stop
        Write-Host "  [OK] OU '$NombreBase' creada." -ForegroundColor Green
        return "OU=$NombreBase,$dcBase"
    } catch {
        Write-Host "  [ERROR] No se pudo crear OU '$NombreBase': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ------------------------------------------------------------
# UTILIDAD: Localizar multiotp.exe
# ------------------------------------------------------------
function Get-MultiOTPExe {
    foreach ($r in @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")) {
        if (Test-Path "$r\multiotp.exe") { return "$r\multiotp.exe" }
    }
    return $null
}

# ------------------------------------------------------------
# UTILIDAD: Permitir login local en el DC a un usuario
# ------------------------------------------------------------
function Habilitar-LogonLocal {
    param([string]$Usuario)
    try {
        $sid     = (Get-ADUser $Usuario -ErrorAction Stop).SID.Value
        $cfgPath = "C:\MFA_Setup\secpol_temp.cfg"
        secedit /export /cfg $cfgPath /quiet 2>&1 | Out-Null
        $contenido = Get-Content $cfgPath -Raw
        if ($contenido -match "SeInteractiveLogonRight.*\*$sid") {
            Write-Host "    [OK] ${Usuario}: ya tiene logon local." -ForegroundColor DarkGray
            return
        }
        $contenido = $contenido -replace "(SeInteractiveLogonRight\s*=\s*)(.*)",       "`$1`$2,*$sid"
        $contenido = $contenido -replace "(SeRemoteInteractiveLogonRight\s*=\s*)(.*)", "`$1`$2,*$sid"
        $contenido | Set-Content $cfgPath -Encoding Unicode
        secedit /configure /cfg $cfgPath /db "C:\MFA_Setup\secedit.sdb" /quiet 2>&1 | Out-Null
        Write-Host "    [OK] ${Usuario}: logon local y RDP habilitados." -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] No se pudo habilitar logon para ${Usuario}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# FUNCION 1: Preparar entorno y descargar multiOTP
# ------------------------------------------------------------
function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PREPARAR ENTORNO Y DESCARGAR MFA       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    $proceder   = $true
    $existentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue
    if ($existentes) {
        Write-Host "  [AVISO] Ya hay archivos multiOTP en $rutaDescarga." -ForegroundColor Yellow
        $r = Read-Host "  Descargar la version mas nueva desde GitHub? (s/n)"
        if ($r.ToLower() -ne 's') { $proceder = $false; Write-Host "  [OK] Usando archivos existentes." -ForegroundColor Green }
    }

    if ($proceder) {
        Write-Host "  [INFO] Consultando GitHub API..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            $headers = @{ "User-Agent" = "PowerShell-P09" }
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest" -Headers $headers -UseBasicParsing
            $asset   = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1
            if (-not $asset) { Write-Host "  [ERROR] Sin instalador en el release." -ForegroundColor Red; Read-Host | Out-Null; return }
            $rutaArchivo = "$rutaDescarga\$($asset.name)"
            Write-Host "  [INFO] Descargando $($release.tag_name) ($($asset.name))..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $rutaArchivo -UseBasicParsing -Headers $headers
            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Extrayendo ZIP..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
            }
            Write-Host "  [OK] Descarga completa." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Fallo la descarga: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 2: Crear los 4 usuarios + habilitar logon local
# ------------------------------------------------------------
function Crear-UsuariosAdmin {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CREACION DE USUARIOS ADMINISTRATIVOS   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $usuarios = @(
        @{ Sam = "admin_identidad"; Nombre = "Admin Identidad"; Desc = "Rol 1 - IAM Operator" },
        @{ Sam = "admin_storage";   Nombre = "Admin Storage";   Desc = "Rol 2 - Storage Operator" },
        @{ Sam = "admin_politicas"; Nombre = "Admin Politicas"; Desc = "Rol 3 - GPO Compliance" },
        @{ Sam = "admin_auditoria"; Nombre = "Admin Auditoria"; Desc = "Rol 4 - Security Auditor" }
    )

    $pwdTexto  = "Hardening2026!"
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force
    $creados   = 0
    $omitidos  = 0

    foreach ($u in $usuarios) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue
        if ($existe) {
            Write-Host "  [OMITIDO] '$($u.Sam)' ya existe en AD." -ForegroundColor Yellow
            $omitidos++
        } else {
            try {
                New-ADUser -Name $u.Nombre -SamAccountName $u.Sam `
                    -UserPrincipalName "$($u.Sam)@$((Get-ADDomain).DNSRoot)" `
                    -Description $u.Desc -AccountPassword $pwdSegura `
                    -Enabled $true -PasswordNeverExpires $true
                Write-Host "  [OK] '$($u.Sam)' creado. Pass: $pwdTexto" -ForegroundColor Green
                $creados++
            } catch {
                Write-Host "  [ERROR] '$($u.Sam)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n  Configurando permisos de inicio de sesion..." -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity "Remote Desktop Users" -Members $u.Sam -ErrorAction Stop
            Write-Host "  [OK] '$($u.Sam)' en Remote Desktop Users." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] '$($u.Sam)' ya esta en Remote Desktop Users." -ForegroundColor DarkGray
        }
    }

    Write-Host "`n  Habilitando logon local en el DC..." -ForegroundColor Yellow
    if (-not (Test-Path "C:\MFA_Setup")) { New-Item "C:\MFA_Setup" -ItemType Directory | Out-Null }
    foreach ($u in $usuarios) { Habilitar-LogonLocal -Usuario $u.Sam }

    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO actualizada." -ForegroundColor Green
    Write-Host "`n  Resumen: $creados creados, $omitidos ya existian." -ForegroundColor Cyan
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 3: Aplicar permisos RBAC con delegacion por ACL
# ------------------------------------------------------------
function Aplicar-PermisosRBAC {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   APLICAR PERMISOS RBAC Y DELEGACION     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try { $dominio = Get-ADDomain -ErrorAction Stop }
    catch { Write-Host "  [ERROR] No se puede conectar a AD." -ForegroundColor Red; Read-Host | Out-Null; return }

    $dcBase  = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName
    $ouCuates   = Get-OUSegura -NombreBase "Cuates"
    $ouNoCuates = Get-OUSegura -NombreBase "NoCuates"
    if (-not $ouCuates -or -not $ouNoCuates) {
        Write-Host "  [ERROR] No se pudieron resolver las OUs." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    Write-Host "  OU Cuates   : $ouCuates"    -ForegroundColor DarkGray
    Write-Host "  OU NoCuates : $ouNoCuates`n" -ForegroundColor DarkGray

    Write-Host "  [ROL 1] admin_identidad (IAM Operator)..." -ForegroundColor Yellow
    foreach ($ou in @($ouCuates, $ouNoCuates)) {
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:CCDC;;user"                           2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:CA;Reset Password;user"               2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:CA;Change Password;user"              2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:WP;pwdLastSet;user"                   2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;telephoneNumber;user"            2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;physicalDeliveryOfficeName;user" 2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;mail;user"                       2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;lockoutTime;user"                2>&1 | Out-Null
    }
    Write-Host "  [OK] admin_identidad: Control total sobre usuarios en ambas OUs." -ForegroundColor Green

    Write-Host "`n  [ROL 2] admin_storage -- DENY Reset Password..." -ForegroundColor Yellow
    dsacls "$dcBase" /I:S /D "${netbios}\admin_storage:CA;Reset Password;user" 2>&1 | Out-Null
    Write-Host "  [OK] admin_storage: DENEGADO Reset Password en todo el dominio." -ForegroundColor Green

    Write-Host "`n  [ROL 3] admin_politicas (GPO Compliance)..." -ForegroundColor Yellow
    try {
        Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction Stop
        Write-Host "  [OK] Agregado a 'Group Policy Creator Owners'." -ForegroundColor Green
    } catch { Write-Host "  [AVISO] Ya pertenece a 'Group Policy Creator Owners'." -ForegroundColor DarkGray }
    dsacls "$dcBase" /I:T /G "${netbios}\admin_politicas:GR" 2>&1 | Out-Null
    foreach ($ou in @($ouCuates, $ouNoCuates)) {
        dsacls "$ou" /I:T /G "${netbios}\admin_politicas:RPWP;gPLink"    2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_politicas:RPWP;gPOptions" 2>&1 | Out-Null
    }
    Write-Host "  [OK] admin_politicas: Lectura dominio + escritura GPOs en OUs." -ForegroundColor Green

    Write-Host "`n  [ROL 4] admin_auditoria (Security Auditor)..." -ForegroundColor Yellow
    try {
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
        Write-Host "  [OK] Agregado a 'Event Log Readers'." -ForegroundColor Green
    } catch { Write-Host "  [AVISO] Ya pertenece a 'Event Log Readers'." -ForegroundColor DarkGray }
    dsacls "$dcBase" /I:T /G "${netbios}\admin_auditoria:GR" 2>&1 | Out-Null
    Write-Host "  [OK] admin_auditoria: Solo lectura en todo el dominio." -ForegroundColor Green

    Write-Host "`n  RBAC aplicado correctamente." -ForegroundColor Green
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 4: Configurar directivas de contrasena (FGPP)
# ------------------------------------------------------------
function Configurar-FGPP {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR DIRECTIVAS FGPP (PSOs)      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try { Get-ADDomain -ErrorAction Stop | Out-Null }
    catch { Write-Host "  [ERROR] No hay conexion a AD." -ForegroundColor Red; Read-Host | Out-Null; return }

    $fgppAdmin = "P09-FGPP-Admins"
    Write-Host "  [1/2] FGPP Administradores (12 chars, prioridad 10)..." -ForegroundColor Yellow
    try {
        $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'" -ErrorAction SilentlyContinue
        if ($existe) {
            Set-ADFineGrainedPasswordPolicy -Identity $fgppAdmin -MinPasswordLength 12 `
                -LockoutThreshold 3 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00"
            Write-Host "  [OK] '$fgppAdmin' actualizada." -ForegroundColor Yellow
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppAdmin `
                -DisplayName "FGPP Alta Seguridad - Administradores" `
                -Precedence 10 -ComplexityEnabled $true -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 5 -MinPasswordLength 12 `
                -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 3 -LockoutObservationWindow "00:30:00" -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] '$fgppAdmin': 12 chars, lockout 3/30min." -ForegroundColor Green
        }
        foreach ($s in @("Domain Admins","admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
            try { Add-ADFineGrainedPasswordPolicySubject -Identity $fgppAdmin -Subjects $s -ErrorAction Stop
                  Write-Host "    [+] Aplicada a: $s" -ForegroundColor DarkGreen } catch {}
        }
    } catch { Write-Host "  [ERROR] FGPP Admins: $($_.Exception.Message)" -ForegroundColor Red }

    $fgppStd = "P09-FGPP-Standard"
    Write-Host "`n  [2/2] FGPP Estandar (8 chars, prioridad 20)..." -ForegroundColor Yellow
    try {
        $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppStd'" -ErrorAction SilentlyContinue
        if ($existe) {
            Set-ADFineGrainedPasswordPolicy -Identity $fgppStd -MinPasswordLength 8
            Write-Host "  [OK] '$fgppStd' actualizada." -ForegroundColor Yellow
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppStd `
                -DisplayName "FGPP Estandar - Cuates y NoCuates" `
                -Precedence 20 -ComplexityEnabled $true -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 3 -MinPasswordLength 8 `
                -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 5 -LockoutObservationWindow "00:15:00" -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] '$fgppStd': 8 chars." -ForegroundColor Green
        }
        foreach ($s in @("Cuates","NoCuates")) {
            try { Add-ADFineGrainedPasswordPolicySubject -Identity $fgppStd -Subjects $s -ErrorAction Stop
                  Write-Host "    [+] Aplicada al grupo: $s" -ForegroundColor DarkGreen }
            catch { Write-Host "    [AVISO] No se pudo aplicar a '$s'." -ForegroundColor DarkGray }
        }
    } catch { Write-Host "  [ERROR] FGPP Standard: $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 5: Configurar auditoria y generar reporte ID 4625
# ------------------------------------------------------------
function Configurar-Auditoria {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   AUDITORIA DE EVENTOS Y REPORTE         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    Write-Host "  [1/3] Habilitando politicas de auditoria..." -ForegroundColor Yellow
    foreach ($p in @("Logon","Account Lockout","File System","Other Object Access Events","User Account Management")) {
        auditpol /set /subcategory:"$p" /success:enable /failure:enable 2>&1 | Out-Null
        Write-Host "  [OK] $p" -ForegroundColor Green
    }

    Write-Host "`n  [2/3] Aplicando GPO..." -ForegroundColor Yellow
    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO actualizada." -ForegroundColor Green

    Write-Host "`n  [3/3] Extrayendo eventos ID 4625..." -ForegroundColor Yellow
    $rutaReporte = "C:\MFA_Setup\Reporte_AccesosDenegados_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
    $enc = "==================================================" + [Environment]::NewLine +
           "REPORTE DE AUDITORIA DE SEGURIDAD"               + [Environment]::NewLine +
           "Practica 09 - Hardening Active Directory"         + [Environment]::NewLine +
           "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" + [Environment]::NewLine +
           "Servidor : $env:COMPUTERNAME"                    + [Environment]::NewLine +
           "Dominio  : $env:USERDNSDOMAIN"                   + [Environment]::NewLine +
           "Evento   : ID 4625 - Inicio de sesion fallido"   + [Environment]::NewLine +
           "==================================================" + [Environment]::NewLine
    try {
        $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue
        $enc | Out-File $rutaReporte -Encoding UTF8
        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [AVISO] Sin eventos ID 4625 aun." -ForegroundColor Yellow
            "No se encontraron eventos de acceso denegado (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
        } else {
            Write-Host "  [OK] $($eventos.Count) evento(s). Exportando..." -ForegroundColor Green
            $i = 1
            foreach ($e in $eventos) {
                $xml  = [xml]$e.ToXml()
                $user = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName"   }).'#text'
                $dom  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
                $ip   = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "IpAddress"        }).'#text'
                ("EVENTO $i de $($eventos.Count)"                               + [Environment]::NewLine +
                 "--------------------------------------------------"           + [Environment]::NewLine +
                 "Fecha    : $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))" + [Environment]::NewLine +
                 "Usuario  : $user"                                              + [Environment]::NewLine +
                 "Dominio  : $dom"                                               + [Environment]::NewLine +
                 "IP origen: $ip"                                                + [Environment]::NewLine +
                 "--------------------------------------------------"           + [Environment]::NewLine
                ) | Out-File $rutaReporte -Append -Encoding UTF8
                $i++
            }
        }
        Write-Host "  [OK] Reporte: $rutaReporte" -ForegroundColor Green
        Write-Host "`n  --- CONTENIDO ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" }
        Write-Host "  -----------------" -ForegroundColor Cyan
    } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 6: Instalar VC++ 2022 y multiOTP
# ------------------------------------------------------------
function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   INSTALAR DEPENDENCIAS Y MOTOR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    $multiotpExe  = Get-MultiOTPExe
    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP ya instalado: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $r = Read-Host "  Reconfigurar? (s/n)"
        if ($r.ToLower() -ne 's') { Write-Host "  Ve a la Opcion 7." -ForegroundColor Yellow; Read-Host | Out-Null; return }
    }

    Write-Host "  [1/2] Visual C++ 2022 Redistributable..." -ForegroundColor Yellow
    $vcPath = "$rutaDescarga\vc_redist_2022_x64.exe"
    if (-not (Test-Path $vcPath)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcPath -UseBasicParsing
        } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red; Read-Host | Out-Null; return }
    }
    $p = Start-Process $vcPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($p.ExitCode -in @(0,1638,3010)) { Write-Host "  [OK] VC++ listo." -ForegroundColor Green }
    Start-Sleep -Seconds 2

    Write-Host "`n  [2/2] Instalador multiOTP..." -ForegroundColor Yellow
    Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = "$rutaDescarga\Extracted_$($_.BaseName)"
        if (-not (Test-Path $dest)) { Expand-Archive -Path $_.FullName -DestinationPath $dest -Force }
    }
    $instalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
                  Sort-Object Length -Descending | Select-Object -First 1
    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro instalador. Ejecuta Opcion 1." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    Write-Host "`n  INSTRUCCIONES DEL INSTALADOR:" -ForegroundColor Yellow
    Write-Host "  1. Marca: 'No remote server, local multiOTP only'" -ForegroundColor White
    Write-Host "  2. Logon  -> 'Local and Remote'"                   -ForegroundColor White
    Write-Host "  3. Unlock -> 'Local and Remote'"                   -ForegroundColor White
    Write-Host "  4. Next hasta Finish."                             -ForegroundColor White
    Write-Host "  Presiona Enter para lanzar..."
    Read-Host | Out-Null
    try {
        if ($instalador.Extension -eq ".msi") { $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$($instalador.FullName)`"" -Wait -PassThru }
        else { $p = Start-Process $instalador.FullName -Wait -PassThru }
        if ($p.ExitCode -eq 0) { Write-Host "  [OK] multiOTP instalado." -ForegroundColor Green }
        else { Write-Host "  [AVISO] Codigo $($p.ExitCode)." -ForegroundColor Yellow }
    } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 7: Registrar TODOS los admins en multiOTP
# ------------------------------------------------------------
function Activar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   ACTIVAR MFA Y GENERAR CLAVE TOTP       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $multiotpExe = Get-MultiOTPExe
    if (-not $multiotpExe) {
        Write-Host "  [ERROR] multiotp.exe no encontrado. Ejecuta Opcion 6." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    $dir = Split-Path $multiotpExe
    Push-Location $dir

    $netbios = $env:USERDOMAIN
    $dns     = $env:USERDNSDOMAIN
    if ([string]::IsNullOrWhiteSpace($dns)) { $dns = (Get-ADDomain).DNSRoot }

    $base32    = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $miSecreto = -join ((1..16) | ForEach-Object { $base32[(Get-Random -Maximum 32)] })
    Write-Host "  [INFO] Secreto maestro: $miSecreto`n" -ForegroundColor DarkGray

    $usuarios = @("Administrator","admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    $totalOK  = 0
    foreach ($u in $usuarios) {
        Write-Host "  Registrando: $u ..." -ForegroundColor Yellow
        foreach ($id in @($u, "$netbios\$u", "$u@$dns")) {
            & ".\multiotp.exe" -delete $id 2>&1 | Out-Null
            $s = & ".\multiotp.exe" -create $id TOTP $miSecreto 6 2>&1
            if ($s -match "(?i)(ok|success|created|0)") {
                Write-Host "    [OK] $id" -ForegroundColor Green; $totalOK++
            } else {
                Write-Host "    [WARN] $id -> $s" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`n  Configurando bloqueo (3 fallos = 30 min)..." -ForegroundColor Yellow
    & ".\multiotp.exe" -config MaxDelayedFailures=3       2>&1 | Out-Null
    & ".\multiotp.exe" -config MaxBlockFailures=3         2>&1 | Out-Null
    & ".\multiotp.exe" -config FailureDelayInSeconds=1800 2>&1 | Out-Null
    Write-Host "  [OK] Bloqueo configurado." -ForegroundColor Green
    Pop-Location

    $archivo = "C:\MFA_Setup\MFA_Secret_TodosAdmins.txt"
    @("MFA TOTP Secret - Practica 09","==============================",
      "Usuarios : Administrator, admin_identidad, admin_storage, admin_politicas, admin_auditoria",
      "Servidor : $env:COMPUTERNAME","Dominio  : $netbios ($dns)",
      "Secreto  : $miSecreto","Tipo     : TOTP RFC 6238 (Google Authenticator)",
      "Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
      "","NOTA: Todos los usuarios comparten el mismo secreto TOTP."
    ) | Out-File $archivo -Encoding UTF8

    Write-Host "`n  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |   ACTUALIZA GOOGLE AUTHENTICATOR                         |" -ForegroundColor Magenta
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  IMPORTANTE: Borra la entrada vieja y agrega una nueva:"      -ForegroundColor Red
    Write-Host ""
    Write-Host "     Nombre : Practica09 - $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "     Secreto: $miSecreto"                     -ForegroundColor Green
    Write-Host "     Tipo   : Basada en tiempo (TOTP)"        -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Sirve para TODOS: Administrator, admin_identidad, admin_storage," -ForegroundColor White
    Write-Host "  admin_politicas y admin_auditoria."                               -ForegroundColor White
    Write-Host "`n  [OK] Secreto guardado en: $archivo"                            -ForegroundColor Green
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 8: Ejecutar tests automatizados
# ------------------------------------------------------------
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
