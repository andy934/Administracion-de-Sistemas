# ============================================================
#   configuracion.ps1
#   Funciones de instalacion y configuracion del servidor FTP
#   Se importa desde ftp-config.ps1 con . .\configuracion.ps1
# ============================================================

$FTP_ROOT  = "C:\inetpub\ftproot"
$SITE_NAME = "FTP-Sistemas"
$GRUPOS    = @("reprobados", "recursadores")

# ── Importar modulo WebAdministration ────────────────────────
function Importar-WebAdmin {
    if (-not (Get-Module -Name WebAdministration -ErrorAction SilentlyContinue)) {
        try {
            Import-Module WebAdministration -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] No se pudo importar WebAdministration. Instale IIS primero (opcion 1)." `
                -ForegroundColor Red
            return $false
        }
    }
    return $true
}

# ============================================================
# Instalar IIS + FTP Service (idempotente)
# ============================================================
function Instalar-IIS-FTP {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " INSTALACION DE IIS + FTP SERVICE"        -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Idempotencia: verificar si ya esta instalado
    $ftpInstalado = Get-WindowsFeature -Name "Web-Ftp-Server" |
                    Where-Object { $_.InstallState -eq "Installed" }

    if ($ftpInstalado) {
        Write-Host "[INFO] IIS FTP ya esta instalado. Omitiendo instalacion." -ForegroundColor Yellow
    } else {
        Write-Host "[INSTALANDO] Web-Server, Web-Ftp-Server, Web-Mgmt-Console..."
        Install-WindowsFeature `
            -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service, Web-Mgmt-Console `
            -IncludeManagementTools `
            -ErrorAction Stop
        Write-Host "[OK] IIS y FTP Service instalados." -ForegroundColor Green
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    Crear-Estructura-Directorios
    Crear-Sitio-FTP
    Configurar-Firewall

    $svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 |
               Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
               Select-Object -First 1).IPAddress
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "[OK] Servidor FTP activo y configurado"    -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "  Directorio base : $FTP_ROOT"
        Write-Host "  Sitio IIS       : $SITE_NAME"
        Write-Host "  Puerto          : 21"
        Write-Host "  IP del servidor : $ip"
        Write-Host ""
    } else {
        Write-Host "[ERROR] El servicio FTPSVC no esta corriendo." -ForegroundColor Red
    }
}

# ============================================================
# Crear estructura de directorios y permisos NTFS
# ============================================================
function Crear-Estructura-Directorios {
    Write-Host "[INFO] Creando estructura de directorios FTP..."

    $dirs = @(
        $FTP_ROOT,
        "$FTP_ROOT\general",
        "$FTP_ROOT\reprobados",
        "$FTP_ROOT\recursadores",
        "$FTP_ROOT\usuarios",
        "$FTP_ROOT\LocalUser"
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "[OK] Creado: $dir"
        }
    }

    # Crear grupos locales si no existen
    foreach ($grupo in $GRUPOS) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo -Description "Grupo FTP $grupo"
            Write-Host "[OK] Grupo '$grupo' creado." -ForegroundColor Green
        } else {
            Write-Host "[INFO] Grupo '$grupo' ya existe."
        }
    }

    # Permisos NTFS
    # general: Everyone lectura, Authenticated Users escritura
    Establecer-Permisos-NTFS "$FTP_ROOT\general"     "Everyone"             "ReadAndExecute"
    Establecer-Permisos-NTFS "$FTP_ROOT\general"     "Authenticated Users"  "Modify"
    # carpetas de grupo: solo el grupo escribe
    Establecer-Permisos-NTFS "$FTP_ROOT\reprobados"  "reprobados"           "Modify"
    Establecer-Permisos-NTFS "$FTP_ROOT\recursadores" "recursadores"        "Modify"

    Write-Host "[OK] Estructura de directorios y permisos NTFS configurados." -ForegroundColor Green
}

# ============================================================
# Aplicar un permiso NTFS (ACL) a una ruta
# ============================================================
function Establecer-Permisos-NTFS {
    param(
        [string]$Ruta,
        [string]$Cuenta,
        [string]$Permiso,
        [string]$Tipo = "Allow"
    )
    try {
        $acl   = Get-Acl -Path $Ruta
        $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Cuenta, $Permiso,
            "ContainerInherit,ObjectInherit",
            "None", $Tipo
        )
        $acl.SetAccessRule($regla)
        Set-Acl -Path $Ruta -AclObject $acl
    } catch {
        Write-Host "[WARN] No se pudo aplicar '$Permiso' a '$Cuenta' en '$Ruta': $_" `
            -ForegroundColor Yellow
    }
}

# ============================================================
# Crear sitio FTP en IIS con aislamiento de usuarios
# ============================================================
function Crear-Sitio-FTP {
    if (-not (Importar-WebAdmin)) { return }

    $sitioExiste = Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    if ($sitioExiste) {
        Write-Host "[INFO] Sitio '$SITE_NAME' ya existe. Omitiendo creacion."
        return
    }

    Write-Host "[INFO] Creando sitio FTP '$SITE_NAME'..."

    New-WebFtpSite -Name $SITE_NAME -Port 21 -PhysicalPath $FTP_ROOT -Force

    # Autenticacion anonima + basica
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled    -Value $true

    # SSL no requerido
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

    # Puertos pasivos
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
        -Name "lowDataChannelPort"  -Value 40000 -PSPath "IIS:\"
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
        -Name "highDataChannelPort" -Value 40100 -PSPath "IIS:\"

    # Reglas de autorizacion FTP
    Clear-WebConfiguration `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$SITE_NAME" -ErrorAction SilentlyContinue

    # Anonimo: solo lectura
    Add-WebConfiguration -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$SITE_NAME" `
        -Value @{ accessType = "Allow"; users = ""; roles = ""; permissions = "Read" }

    # Autenticados: lectura + escritura
    Add-WebConfiguration -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$SITE_NAME" `
        -Value @{ accessType = "Allow"; users = "*"; roles = ""; permissions = "Read, Write" }

    # Aislamiento de usuarios: cada usuario ve solo su carpeta en LocalUser\$usuario
    Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
        -Name ftpServer.userIsolation.mode -Value 3

    Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    Set-Service   -Name "FTPSVC" -StartupType Automatic
    Start-Service -Name "FTPSVC" -ErrorAction SilentlyContinue

    Write-Host "[OK] Sitio FTP '$SITE_NAME' creado y configurado." -ForegroundColor Green
}

# ============================================================
# Configurar reglas de Firewall para FTP
# ============================================================
function Configurar-Firewall {
    Write-Host "[INFO] Configurando firewall para FTP..."

    if (-not (Get-NetFirewallRule -DisplayName "FTP-Puerto-21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP-Puerto-21" `
            -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }
    if (-not (Get-NetFirewallRule -DisplayName "FTP-Pasivo-40000-40100" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP-Pasivo-40000-40100" `
            -Direction Inbound -Protocol TCP -LocalPort 40000-40100 -Action Allow | Out-Null
    }

    Write-Host "[OK] Firewall configurado (21 y 40000-40100)." -ForegroundColor Green
}

# ============================================================
# Ver estado del servicio FTP
# ============================================================
function Ver-Estado-Servicio {
    Write-Host ""
    Write-Host "=== ESTADO DEL SERVICIO FTP ===" -ForegroundColor Cyan
    Write-Host ""

    $svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  Servicio : $($svc.DisplayName)"
        Write-Host "  Estado   : $($svc.Status)"
        Write-Host "  Inicio   : $($svc.StartType)"
    } else {
        Write-Host "[ERROR] El servicio FTPSVC no esta instalado." -ForegroundColor Red
        return
    }

    if (Importar-WebAdmin) {
        $sitio = Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
        if ($sitio) {
            Write-Host ""
            Write-Host "  Sitio IIS    : $($sitio.Name)"
            Write-Host "  Estado sitio : $($sitio.State)"
            Write-Host "  Ruta fisica  : $($sitio.PhysicalPath)"
            Write-Host "  Puerto       : 21"
        }
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
           Select-Object -First 1).IPAddress
    Write-Host ""
    Write-Host "  IP del servidor : $ip"
    Write-Host "  Conectar con    : ftp $ip"
    Write-Host ""
}

# ============================================================
# Reiniciar servicio FTP
# ============================================================
function Reiniciar-Servicio {
    Write-Host ""
    Write-Host "[INFO] Reiniciando servicio FTPSVC..."
    Restart-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
    $estado = (Get-Service -Name "FTPSVC").Status
    if ($estado -eq "Running") {
        Write-Host "[OK] Servicio reiniciado correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio no pudo reiniciarse. Estado: $estado" -ForegroundColor Red
    }
}

# ============================================================
# Ver logs del servicio FTP
# ============================================================
function Ver-Logs {
    Write-Host ""
    Write-Host "=== LOGS DEL SERVICIO FTP ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Ultimas 50 lineas del log de IIS FTP"
    Write-Host "  2. Log del sistema (Event Viewer - FTPSVC)"
    $op = Read-Host "Opcion (1-2)"

    switch ($op) {
        "1" {
            $logFile = Get-ChildItem "C:\inetpub\logs\LogFiles" -Recurse -Filter "*.log" `
                       -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($logFile) {
                Write-Host "  Archivo: $($logFile.FullName)"; Write-Host ""
                Get-Content $logFile.FullName -Tail 50
            } else {
                Write-Host "[INFO] No hay archivos de log aun."
            }
        }
        "2" {
            Get-EventLog -LogName System -Source "*FTPSVC*" -Newest 20 -ErrorAction SilentlyContinue |
                Format-Table TimeGenerated, EntryType, Message -AutoSize
        }
        default { Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red }
    }
}

# ============================================================
# Probar conexion FTP
# ============================================================
function Probar-Conexion {
    Write-Host ""
    Write-Host "=== PRUEBA DE CONEXION FTP ===" -ForegroundColor Cyan
    Write-Host ""

    $svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne "Running") {
        Write-Host "[ERROR] El servicio FTPSVC no esta corriendo." -ForegroundColor Red
        return
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
           Select-Object -First 1).IPAddress

    Write-Host "  1. Anonimo (lectura en /general)"
    Write-Host "  2. Usuario autenticado"
    $op = Read-Host "Opcion (1-2)"

    switch ($op) {
        "1" {
            Write-Host ""
            Write-Host "  Conexion anonima:"
            Write-Host "    ftp $ip  |  Usuario: anonymous  |  Contrasena: (enter)"
            Write-Host ""
            Write-Host "  FileZilla: ftp://$ip  Puerto: 21  Usuario: anonymous"
        }
        "2" {
            $u = Read-Host "Nombre de usuario"
            Write-Host ""
            Write-Host "  Conexion autenticada:"
            Write-Host "    ftp $ip  |  Usuario: $u  |  Contrasena: (la configurada)"
            Write-Host ""
            Write-Host "  FileZilla: ftp://$ip  Puerto: 21  Usuario: $u"
        }
        default { Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red; return }
    }

    Write-Host ""
    $test = Test-NetConnection -ComputerName $ip -Port 21 -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        Write-Host "  [OK] El servidor esta escuchando en el puerto 21." -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] El servidor NO responde en el puerto 21." -ForegroundColor Red
    }
}
