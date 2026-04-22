# =============================================================================
# func-rbac.ps1 - Creacion de usuarios y delegacion RBAC
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# =============================================================================

function Crear-UsuariosAdmin {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CREACION DE USUARIOS ADMINISTRATIVOS   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $usuarios = @(
        @{ Sam = "admin_identidad"; Nombre = "Admin Identidad"; Desc = "Rol 1 - IAM Operator" },
        @{ Sam = "admin_storage"; Nombre = "Admin Storage"; Desc = "Rol 2 - Storage Operator" },
        @{ Sam = "admin_politicas"; Nombre = "Admin Politicas"; Desc = "Rol 3 - GPO Compliance" },
        @{ Sam = "admin_auditoria"; Nombre = "Admin Auditoria"; Desc = "Rol 4 - Security Auditor" }
    )

    $pwdTexto = "Admin.Uas.2026!"
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force
    $creados = 0
    $omitidos = 0

    foreach ($u in $usuarios) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue
        if ($existe) {
            Write-Host "  [OMITIDO] '$($u.Sam)' ya existe en AD." -ForegroundColor Yellow
            $omitidos++
        }
        else {
            try {
                New-ADUser -Name $u.Nombre -SamAccountName $u.Sam `
                    -UserPrincipalName "$($u.Sam)@$((Get-ADDomain).DNSRoot)" `
                    -Description $u.Desc -AccountPassword $pwdSegura `
                    -Enabled $true -PasswordNeverExpires $true
                Write-Host "  [OK] '$($u.Sam)' creado. Pass: $pwdTexto" -ForegroundColor Green
                $creados++
            }
            catch {
                Write-Host "  [ERROR] '$($u.Sam)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n  Configurando permisos de inicio de sesion..." -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity "Remote Desktop Users" -Members $u.Sam -ErrorAction Stop
            Write-Host "  [OK] '$($u.Sam)' en Remote Desktop Users." -ForegroundColor Green
        }
        catch {
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

    $dcBase = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName
    $ouCuates = Get-OUSegura -NombreBase "Cuates"
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
    }
    catch { Write-Host "  [AVISO] Ya pertenece a 'Group Policy Creator Owners'." -ForegroundColor DarkGray }
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
    }
    catch { Write-Host "  [AVISO] Ya pertenece a 'Event Log Readers'." -ForegroundColor DarkGray }
    dsacls "$dcBase" /I:T /G "${netbios}\admin_auditoria:GR" 2>&1 | Out-Null
    Write-Host "  [OK] admin_auditoria: Solo lectura en todo el dominio." -ForegroundColor Green

    Write-Host "`n  RBAC aplicado correctamente." -ForegroundColor Green
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 4: Configurar directivas de contrasena (FGPP)
# ------------------------------------------------------------

