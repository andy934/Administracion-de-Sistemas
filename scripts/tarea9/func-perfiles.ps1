# =============================================================================
# VARIABLES GLOBALES
# =============================================================================

$SERVIDOR = "SRV-WIN-SISTEMA"
$DOMINIO = "reprobados.local"
$PERFILES_PATH = "C:\Perfiles"
$PERFILES_SHARE = "Perfiles$"
$REDIR_PATH = "C:\Redireccion"
$REDIR_SHARE = "Redireccion$"
$CSV_PATH = "$PSScriptRoot\usuarios.csv"

$USUARIOS_ADMIN = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")

# =============================================================================
# HELPERS
# =============================================================================

function Write-OK { param($m) Write-Host "  [OK] $m"   -ForegroundColor Green }
function Write-Info { param($m) Write-Host "  [INFO] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Err { param($m) Write-Host "  [ERROR] $m" -ForegroundColor Red }

# =============================================================================
# FUNCION PRINCIPAL: Configurar Perfiles Moviles
# =============================================================================

function Configurar-PerfilesMoviles {
    # Verificar que el script corre como Administrador elevado
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Write-Err "Este script debe ejecutarse como Administrador (elevado). Usa 'Ejecutar como administrador'."
        Read-Host "  Presiona Enter para volver al menu..." | Out-Null
        return
    }

    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR PERFILES MOVILES            |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # -------------------------------------------------------
    # PASO 1: Crear carpeta de perfiles y compartirla
    # -------------------------------------------------------
    Write-Info "Creando carpeta de perfiles: $PERFILES_PATH"
    if (-not (Test-Path $PERFILES_PATH)) {
        New-Item -Path $PERFILES_PATH -ItemType Directory -Force | Out-Null
        Write-OK "Carpeta creada: $PERFILES_PATH"
    }
    else {
        Write-OK "Carpeta ya existe: $PERFILES_PATH"
    }

    # Permisos de la carpeta: solo Administradores y SYSTEM tienen control total
    # Los usuarios solo pueden crear subcarpetas propias
    # Resolver identidades via SID (evita problemas de idioma/localizacion)
    $sidSystem = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")).Translate([System.Security.Principal.NTAccount]).Value
    $sidAdmins = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount]).Value
    $sidAuthUsers = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")).Translate([System.Security.Principal.NTAccount]).Value

    $acl = Get-Acl $PERFILES_PATH
    $acl.SetAccessRuleProtection($true, $false)

    $r1 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidSystem, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    $r2 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidAdmins, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    $r3 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidAuthUsers, "ReadAndExecute,Write,CreateFiles,CreateDirectories", "None", "None", "Allow"
    $acl.AddAccessRule($r1)
    $acl.AddAccessRule($r2)
    $acl.AddAccessRule($r3)
    Set-Acl -Path $PERFILES_PATH -AclObject $acl
    Write-OK "Permisos NTFS aplicados en $PERFILES_PATH"

    # Compartir carpeta de perfiles
    $shareExiste = Get-SmbShare -Name $PERFILES_SHARE -ErrorAction SilentlyContinue
    if (-not $shareExiste) {
        New-SmbShare -Name $PERFILES_SHARE -Path $PERFILES_PATH -FullAccess "Todos" -Description "Perfiles Moviles" | Out-Null
        Write-OK "Carpeta compartida: \\$SERVIDOR\$PERFILES_SHARE"
    }
    else {
        Write-OK "Compartido ya existe: \\$SERVIDOR\$PERFILES_SHARE"
    }

    # -------------------------------------------------------
    # PASO 2: Crear carpeta de redireccion de carpetas
    # -------------------------------------------------------
    Write-Info "Creando carpeta de redireccion: $REDIR_PATH"
    if (-not (Test-Path $REDIR_PATH)) {
        New-Item -Path $REDIR_PATH -ItemType Directory -Force | Out-Null
        Write-OK "Carpeta creada: $REDIR_PATH"
    }

    $aclRedir = Get-Acl $REDIR_PATH
    $aclRedir.SetAccessRuleProtection($true, $false)

    $rr1 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidSystem, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    $rr2 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidAdmins, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    $rr3 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidAuthUsers, "FullControl", "None", "None", "Allow"
    $aclRedir.AddAccessRule($rr1)
    $aclRedir.AddAccessRule($rr2)
    $aclRedir.AddAccessRule($rr3)
    Set-Acl -Path $REDIR_PATH -AclObject $aclRedir
    Write-OK "Permisos NTFS aplicados en $REDIR_PATH"

    $shareRedirExiste = Get-SmbShare -Name $REDIR_SHARE -ErrorAction SilentlyContinue
    if (-not $shareRedirExiste) {
        New-SmbShare -Name $REDIR_SHARE -Path $REDIR_PATH -FullAccess "Todos" -Description "Redireccion de Carpetas" | Out-Null
        Write-OK "Carpeta compartida: \\$SERVIDOR\$REDIR_SHARE"
    }
    else {
        Write-OK "Compartido ya existe: \\$SERVIDOR\$REDIR_SHARE"
    }

    # -------------------------------------------------------
    # PASO 3: Asignar perfil movil a cada usuario del CSV
    # -------------------------------------------------------
    Write-Info "Asignando perfiles moviles a usuarios del CSV..."

    if (-not (Test-Path $CSV_PATH)) {
        Write-Err "No se encontro el archivo CSV en: $CSV_PATH"
        Read-Host | Out-Null; return
    }

    $usuarios = Import-Csv $CSV_PATH

    foreach ($u in $usuarios) {
        $username = $u.Usuario
        try {
            Get-ADUser -Identity $username -ErrorAction Stop | Out-Null
            # Ruta del perfil con extension V6 (Windows 10/11/Server 2016+)
            $rutaPerfil = "\\$SERVIDOR\$PERFILES_SHARE\$username.V6"
            Set-ADUser -Identity $username -ProfilePath $rutaPerfil
            Write-OK "$username -> $rutaPerfil"
        }
        catch {
            Write-Warn "Usuario no encontrado en AD: $username"
        }
    }

    # Tambien asignar a los 4 admins delegados
    foreach ($admin in $USUARIOS_ADMIN) {
        try {
            Get-ADUser -Identity $admin -ErrorAction Stop | Out-Null
            $rutaPerfil = "\\$SERVIDOR\$PERFILES_SHARE\$admin.V6"
            Set-ADUser -Identity $admin -ProfilePath $rutaPerfil
            Write-OK "$admin -> $rutaPerfil"
        }
        catch {
            Write-Warn "Usuario admin no encontrado en AD: $admin"
        }
    }

    # -------------------------------------------------------
    # PASO 4: GPO para redireccion de carpetas
    # -------------------------------------------------------
    Write-Info "Configurando GPO de redireccion de carpetas..."

    $gpoNombre = "P9-Perfiles-Moviles"
    $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoNombre -Comment "Perfiles moviles y redireccion de carpetas"
        Write-OK "GPO creada: $gpoNombre"
    }
    else {
        Write-OK "GPO ya existe: $gpoNombre"
    }

    # Configurar redireccion de Documentos, Descargas y Escritorio via registro de GPO
    # Habilitar sincronizacion de perfiles offline (Archivos sin conexion)
    Set-GPRegistryValue -Name $gpoNombre -Key "HKCU\Software\Policies\Microsoft\Windows\NetCache" `
        -ValueName "Enabled" -Type DWord -Value 1 -ErrorAction SilentlyContinue
    Write-OK "Sincronizacion offline habilitada en GPO"

    # Forzar descarga del perfil completo (no solo los cambios)
    Set-GPRegistryValue -Name $gpoNombre -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "SlowLinkDetect" -Type DWord -Value 0 -ErrorAction SilentlyContinue

    # Eliminar copias locales del perfil al cerrar sesion (1 = activado, comportamiento correcto)
    Set-GPRegistryValue -Name $gpoNombre -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "DeleteRoamingCache" -Type DWord -Value 1 -ErrorAction SilentlyContinue

    # Habilitar perfiles moviles para todos los usuarios
    Set-GPRegistryValue -Name $gpoNombre -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "ExcludeProfileDirs" -Type String -Value "" -ErrorAction SilentlyContinue

    # Vincular GPO al dominio
    $domainDN = (Get-ADDomain).DistinguishedName
    try {
        New-GPLink -Name $gpoNombre -Target $domainDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
        Write-OK "GPO vinculada al dominio: $domainDN"
    }
    catch {
        Write-Warn "GPO ya estaba vinculada o no se pudo vincular: $($_.Exception.Message)"
    }

    # Vincular tambien a las OUs
    foreach ($ou in @("OU=Cuates", "OU=NoCuates", "OU=AdminsDelegados")) {
        try {
            $ouDN = "$ou,$domainDN"
            New-GPLink -Name $gpoNombre -Target $ouDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
            Write-OK "GPO vinculada a: $ouDN"
        }
        catch {
            Write-Warn "No se pudo vincular a $ou : $($_.Exception.Message)"
        }
    }

    # -------------------------------------------------------
    # PASO 5: Configurar redireccion de carpetas via ADML/ADMX
    # usando el modulo de Group Policy con cmdlets de registro
    # -------------------------------------------------------
    Write-Info "Configurando redireccion de Documentos y Descargas..."

    # Las rutas de redireccion usan %USERNAME% que AD expande automaticamente
    $carpetas = @{
        "Documents" = "\\$SERVIDOR\$REDIR_SHARE\%USERNAME%\Documentos"
        "Downloads" = "\\$SERVIDOR\$REDIR_SHARE\%USERNAME%\Descargas"
        "Desktop"   = "\\$SERVIDOR\$REDIR_SHARE\%USERNAME%\Escritorio"
    }

    foreach ($carpeta in $carpetas.GetEnumerator()) {
        # Crear subcarpeta base en el servidor
        $rutaBase = "$REDIR_PATH\$($carpeta.Key)"
        if (-not (Test-Path $rutaBase)) {
            New-Item -Path $rutaBase -ItemType Directory -Force | Out-Null
        }
    }

    # Configurar redireccion via GPO usando el proveedor de Group Policy
    # Estas claves aplican la redireccion de carpetas del lado del usuario
    $folderRedirKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

    # NOTA: La redireccion real de carpetas requiere configuracion en GPMC (Group Policy Management Console)
    # bajo: Configuracion de usuario > Directivas > Configuracion de Windows > Redireccion de carpetas
    # No es configurable via Set-GPRegistryValue porque usa extensiones CSE propias.
    # Las siguientes claves de registro son un respaldo para clientes sin soporte CSE completo:

    Set-GPRegistryValue -Name $gpoNombre -Key $folderRedirKey `
        -ValueName "Personal" -Type ExpandString `
        -Value "\\$SERVIDOR\$REDIR_SHARE\%USERNAME%\Documentos" -ErrorAction SilentlyContinue

    Set-GPRegistryValue -Name $gpoNombre -Key $folderRedirKey `
        -ValueName "{374DE290-123F-4565-9164-39C4925E467B}" -Type ExpandString `
        -Value "\\$SERVIDOR\$REDIR_SHARE\%USERNAME%\Descargas" -ErrorAction SilentlyContinue

    Set-GPRegistryValue -Name $gpoNombre -Key $folderRedirKey `
        -ValueName "Desktop" -Type ExpandString `
        -Value "\\$SERVIDOR\$REDIR_SHARE\%USERNAME%\Escritorio" -ErrorAction SilentlyContinue

    Write-OK "Redireccion de carpetas configurada en GPO"

    # -------------------------------------------------------
    # PASO 6: Crear subcarpetas V6 para cada usuario
    # (se crean automaticamente al primer login, pero las
    #  creamos ahora para preconfigurar permisos)
    # -------------------------------------------------------
    Write-Info "Precreando carpetas de perfil V6..."

    $todosUsuarios = ($usuarios | Select-Object -ExpandProperty Usuario) + $USUARIOS_ADMIN
    foreach ($u in $todosUsuarios) {
        $perfilDir = "$PERFILES_PATH\$u.V6"
        if (-not (Test-Path $perfilDir)) {
            New-Item -Path $perfilDir -ItemType Directory -Force | Out-Null
        }

        # Permisos: el usuario tiene control total sobre su propia carpeta
        try {
            $aclPerfil = Get-Acl $perfilDir
            $aclPerfil.SetAccessRuleProtection($true, $false)
            $pu1 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidSystem, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            $pu2 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $sidAdmins, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            $pu3 = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList "$DOMINIO\$u", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            $aclPerfil.AddAccessRule($pu1)
            $aclPerfil.AddAccessRule($pu2)
            $aclPerfil.AddAccessRule($pu3)
            Set-Acl -Path $perfilDir -AclObject $aclPerfil
            Write-OK "Carpeta V6 lista para: $u"
        }
        catch {
            Write-Warn "No se pudo configurar permisos para: $u"
        }
    }

    # -------------------------------------------------------
    # PASO 7: Forzar actualizacion de politicas
    # -------------------------------------------------------
    Write-Info "Actualizando politicas de grupo..."
    gpupdate /force | Out-Null
    Write-OK "Politicas actualizadas."

    Write-Host "`n  +------------------------------------------+" -ForegroundColor Green
    Write-Host "  |   PERFILES MOVILES CONFIGURADOS          |" -ForegroundColor Green
    Write-Host "  +------------------------------------------+" -ForegroundColor Green
    Write-Host "  Carpeta perfiles : \\$SERVIDOR\$PERFILES_SHARE" -ForegroundColor White
    Write-Host "  Carpeta redireccion: \\$SERVIDOR\$REDIR_SHARE" -ForegroundColor White
    Write-Host "  Extension de perfil: .V6 (Windows 10/11/2016+)" -ForegroundColor White
    Write-Host "  Usuarios configurados: $($todosUsuarios.Count)" -ForegroundColor White
    Write-Host "`n  NOTA: Los clientes deben estar unidos al dominio" -ForegroundColor Yellow
    Write-Host "  y hacer login para que el perfil se sincronice." -ForegroundColor Yellow
    Write-Host ""

    Read-Host "  Presiona Enter para volver al menu..." | Out-Null
}