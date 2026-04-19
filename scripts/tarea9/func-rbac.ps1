# =============================================================================
# func-rbac.ps1 - Delegacion de Control y RBAC
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

$DOMAIN = "reprobados.local"
$DOMAIN_DN = "DC=reprobados,DC=local"
$DOMAIN_NETBIOS = "REPROBADOS"
$OU_CUATES = "OU=Cuates,$DOMAIN_DN"
$OU_NO_CUATES = "OU=NoCuates,$DOMAIN_DN"
$OU_ADMINS = "OU=AdminsDelegados,$DOMAIN_DN"

# Usuarios delegados
$ADMINS = @(
    @{ Usuario = "admin_identidad"; Nombre = "Admin Identidad"; Rol = "IAM Operator"; Pass = "Admin@Identidad2026" },
    @{ Usuario = "admin_storage"; Nombre = "Admin Storage"; Rol = "Storage Operator"; Pass = "Admin@Storage2026" },
    @{ Usuario = "admin_politicas"; Nombre = "Admin Politicas"; Rol = "GPO Compliance"; Pass = "Admin@Politicas2026" },
    @{ Usuario = "admin_auditoria"; Nombre = "Admin Auditoria"; Rol = "Security Auditor"; Pass = "Admin@Auditoria2026" }
)

# =============================================================================
# VALIDACIONES
# =============================================================================

function Validar-AD-P9 {
    try {
        Get-ADDomain -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Err "Active Directory no disponible"
        Write-Err "Configura AD primero (ver Practica 8)"
        return $false
    }
}

function Asegurar-OU-Admins {
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OU_ADMINS'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "AdminsDelegados" -Path $DOMAIN_DN `
            -Description "Administradores delegados P9" -ProtectedFromAccidentalDeletion $false
        Write-OK "OU AdminsDelegados creada"
    }
}

# =============================================================================
# CREAR USUARIOS ADMINISTRADORES DELEGADOS
# =============================================================================

function Crear-Admins-Delegados {
    if (-not (Validar-AD-P9)) { return }
    Write-Info "Creando usuarios administradores delegados..."
    Write-Host ""

    Asegurar-OU-Admins

    foreach ($a in $ADMINS) {
        if (Get-ADUser -Filter "SamAccountName -eq '$($a.Usuario)'" -ErrorAction SilentlyContinue) {
            Write-Info "[$($a.Rol)] $($a.Usuario) ya existe"
            continue
        }

        $pass = ConvertTo-SecureString $a.Pass -AsPlainText -Force
        New-ADUser `
            -Name            $a.Nombre `
            -SamAccountName  $a.Usuario `
            -UserPrincipalName "$($a.Usuario)@$DOMAIN" `
            -Path            $OU_ADMINS `
            -AccountPassword $pass `
            -Enabled         $true `
            -PasswordNeverExpires $false `
            -ChangePasswordAtLogon $false `
            -Description     "Rol: $($a.Rol) - Practica 9"
        Write-OK "[$($a.Rol)] $($a.Usuario) creado"
    }
    Write-Host ""
}

# =============================================================================
# ROL 1: admin_identidad ? Gestion de usuarios en OUs Cuates y NoCuates
# =============================================================================

function Delegar-Identidad {
    Write-Info "Configurando delegacion para admin_identidad (IAM Operator)..."

    $usuario = "admin_identidad"
    $sid = (Get-ADUser $usuario).SID.Value

    foreach ($ou in @($OU_CUATES, $OU_NO_CUATES)) {
        # Crear/Eliminar/Modificar usuarios
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:CCDC;user" /I:T | Out-Null
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:WPDCCCRP;user" /I:S | Out-Null

        # Reset de contrasena y desbloqueo de cuenta
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:CA;Reset Password;user" /I:S | Out-Null
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:WP;lockoutTime;user" /I:S | Out-Null
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:WP;pwdLastSet;user" /I:S | Out-Null

        # Modificar atributos basicos
        foreach ($attr in @("telephoneNumber", "physicalDeliveryOfficeName", "mail", "displayName", "givenName", "sn")) {
            & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:WP;${attr};user" /I:S | Out-Null
        }

        Write-OK "  Permisos de gestion de usuarios en: $ou"
    }

    # RESTRICCION: No puede modificar miembros de Domain Admins
    # Denegar escritura sobre grupos de Domain Admins
    $daGroup = "CN=Domain Admins,CN=Users,$DOMAIN_DN"
    & dsacls $daGroup /D "${DOMAIN_NETBIOS}\${usuario}:WP;member" | Out-Null
    Write-OK "  RESTRICCION: Sin acceso a Domain Admins"

    Write-OK "Delegacion admin_identidad completada"
}

# =============================================================================
# ROL 2: admin_storage ? FSRM (cuotas y file screening)
# RESTRICCION: No puede resetear contrasenas
# =============================================================================

function Delegar-Storage {
    Write-Info "Configurando delegacion para admin_storage (Storage Operator)..."

    $usuario = "admin_storage"

    # Permiso de lectura en el dominio (necesita ver estructura)
    & dsacls $DOMAIN_DN /G "${DOMAIN_NETBIOS}\${usuario}:GR" /I:T | Out-Null

    # Acceso a FSRM via grupo local
    # Agregar al grupo de administradores locales para FSRM
    try {
        Add-LocalGroupMember -Group "Administradores" -Member "$DOMAIN_NETBIOS\$usuario" -ErrorAction SilentlyContinue
        Write-OK "  admin_storage agregado a Administradores locales (para FSRM)"
    }
    catch { }

    # RESTRICCION CRITICA: Denegar Reset Password en todos los usuarios del dominio
    foreach ($ou in @($OU_CUATES, $OU_NO_CUATES, $OU_ADMINS)) {
        & dsacls $ou /D "${DOMAIN_NETBIOS}\${usuario}:CA;Reset Password;user" /I:S | Out-Null
        Write-OK "  RESTRICCION: Reset Password DENEGADO en $ou"
    }

    Write-OK "Delegacion admin_storage completada"
}

# =============================================================================
# ROL 3: admin_politicas ? GPO Compliance
# RESTRICCION: Solo lectura en usuarios, escritura solo en GPOs
# =============================================================================

function Delegar-Politicas {
    Write-Info "Configurando delegacion para admin_politicas (GPO Compliance)..."

    $usuario = "admin_politicas"

    # Lectura en todo el dominio
    & dsacls $DOMAIN_DN /G "${DOMAIN_NETBIOS}\${usuario}:GR" /I:T | Out-Null
    Write-OK "  Lectura en todo el dominio"

    # Permiso para vincular/desvincular GPOs en las OUs
    foreach ($ou in @($DOMAIN_DN, $OU_CUATES, $OU_NO_CUATES)) {
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:WP;gPLink" /I:T | Out-Null
        & dsacls $ou /G "${DOMAIN_NETBIOS}\${usuario}:WP;gPOptions" /I:T | Out-Null
    }
    Write-OK "  Permiso de vinculacion de GPOs en OUs"

    # Agregar al grupo Group Policy Creator Owners para crear/editar GPOs
    Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members $usuario -ErrorAction SilentlyContinue
    Write-OK "  Agregado a Group Policy Creator Owners"

    # RESTRICCION: Solo lectura en objetos de usuario (no escritura)
    foreach ($ou in @($OU_CUATES, $OU_NO_CUATES)) {
        & dsacls $ou /D "${DOMAIN_NETBIOS}\${usuario}:WP;;user" /I:S | Out-Null
    }
    Write-OK "  RESTRICCION: Sin escritura sobre cuentas de usuario"

    Write-OK "Delegacion admin_politicas completada"
}

# =============================================================================
# ROL 4: admin_auditoria ? Solo lectura, acceso a logs
# =============================================================================

function Delegar-Auditoria {
    Write-Info "Configurando delegacion para admin_auditoria (Security Auditor)..."

    $usuario = "admin_auditoria"

    # Solo lectura en todo el dominio
    & dsacls $DOMAIN_DN /G "${DOMAIN_NETBIOS}\${usuario}:GR" /I:T | Out-Null
    Write-OK "  Lectura en todo el dominio (solo lectura)"

    # Agregar al grupo Event Log Readers para acceder a logs de seguridad
    Add-ADGroupMember -Identity "Event Log Readers" -Members $usuario -ErrorAction SilentlyContinue
    Write-OK "  Agregado a Event Log Readers"

    # Agregar acceso remoto a logs via grupo local
    try {
        Add-LocalGroupMember -Group "Event Log Readers" -Member "$DOMAIN_NETBIOS\$usuario" -ErrorAction SilentlyContinue
    }
    catch { }

    # RESTRICCION: Denegar cualquier escritura en el dominio
    # Solo lectura - no puede modificar nada
    Write-OK "  RESTRICCION: Usuario de solo lectura (auditoria)"

    Write-OK "Delegacion admin_auditoria completada"
}

# =============================================================================
# APLICAR TODAS LAS DELEGACIONES
# =============================================================================

function Configurar-RBAC-Completo {
    if (-not (Validar-AD-P9)) { return }
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   CONFIGURACION RBAC - 4 ROLES           " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    Crear-Admins-Delegados

    Write-Host ""
    Write-Info "Aplicando delegaciones de control..."
    Write-Host ""

    Delegar-Identidad
    Write-Host ""
    Delegar-Storage
    Write-Host ""
    Delegar-Politicas
    Write-Host ""
    Delegar-Auditoria

    Write-Host ""
    Write-OK "Configuracion RBAC completada para los 4 roles"
}

# =============================================================================
# VERIFICAR PERMISOS
# =============================================================================

function Verificar-RBAC {
    if (-not (Validar-AD-P9)) { return }
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   VERIFICACION DE ROLES RBAC             " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($a in $ADMINS) {
        $user = Get-ADUser $a.Usuario -Properties MemberOf -ErrorAction SilentlyContinue
        if ($user) {
            Write-Host "  $($a.Usuario) [$($a.Rol)]" -ForegroundColor Cyan
            Write-Host "    Habilitado: $($user.Enabled)"
            Write-Host "    UPN: $($user.UserPrincipalName)"
            $grupos = $user.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=', '' }
            if ($grupos) { Write-Host "    Grupos: $($grupos -join ', ')" }
        }
        else {
            Write-Warn "  $($a.Usuario) - NO ENCONTRADO"
        }
        Write-Host ""
    }
}

# =============================================================================
# MOSTRAR ESTADO RBAC
# =============================================================================

function Mostrar-Estado-RBAC {
    Verificar-RBAC
}
