# =============================================================================
# func-install-win.ps1 - Orquestador instalacion hibrida WEB/FTP Windows
# Practica 7 - Administracion de Sistemas
# Reutiliza funciones de Practica 6 (http-func.ps1)
# =============================================================================

$ScriptDir  = Split-Path $MyInvocation.MyCommand.Path -Parent
$P6Func     = "$ScriptDir\..\tarea6\http-func.ps1"
$InstallTmp = "$env:TEMP\tarea7_install"
New-Item -ItemType Directory -Force -Path $InstallTmp | Out-Null

$script:P6Cargado = $false

# Puertos actuales de P6 (detectados o configurados)
$script:PuertoIIS       = 222
$script:PuertoApacheHTTP = 223
$script:PuertoNginxHTTP  = 204

# =============================================================================
# CARGAR FUNCIONES DE P6
# =============================================================================

function Cargar-P6 {
    if ($script:P6Cargado) { return $true }
    if (Test-Path $P6Func) {
        . $P6Func
        $script:P6Cargado = $true
        return $true
    }
    Write-Warn "No se encontro $P6Func"
    Write-Warn "Para instalar desde WEB los scripts de P6 deben estar en:"
    Write-Warn "  $P6Func"
    return $false
}

# =============================================================================
# ELEGIR FUENTE DE INSTALACION
# =============================================================================

function Elegir-Fuente {
    Write-Host ""
    Write-Host "  Fuente de instalacion:" -ForegroundColor Cyan
    Write-Host "    1. WEB — desde repositorio oficial en internet"
    Write-Host "    2. FTP — desde repositorio privado local (IIS-FTP)"
    Write-Host ""
    $fuente = ""
    while ($fuente -ne "1" -and $fuente -ne "2") {
        $fuente = Read-Host "  Seleccione fuente (1/2)"
    }
    $script:FuenteInstalacion = $fuente
}

# =============================================================================
# INSTALACION DESDE WEB (delega a P6)
# =============================================================================

function Instalar-Web {
    param([string]$Servicio)

    if (-not (Cargar-P6)) { return $false }

    Write-Info "Instalando $Servicio desde WEB (Practica 6)..."
    switch ($Servicio) {
        "iis"    { Instalar-IIS    -Puerto $script:PuertoIIS }
        "apache" { Instalar-Apache-Win }
        "nginx"  { Instalar-Nginx-Win }
        default  { Write-Err "Servicio desconocido: $Servicio"; return $false }
    }
    return $true
}

# =============================================================================
# INSTALACION DESDE FTP
# =============================================================================

function Instalar-FTP {
    param([string]$Servicio)

    if (-not (Validar-Repo)) { return $false }

    $svcDir = switch ($Servicio) {
        "iis"    { "IIS" }
        "apache" { "Apache" }
        "nginx"  { "Nginx" }
        default  { Write-Err "Servicio desconocido: $Servicio"; return $false }
    }

    # Navegar repo FTP
    if (-not (Seleccionar-Desde-FTP $svcDir)) { return $false }

    # Descargar binario
    $destino = "$InstallTmp\$($script:ArchivoFTPSeleccionado)"
    if (-not (Descargar-FTP $script:RutaFTPSeleccionada $destino)) { return $false }

    # Verificar hash SHA256
    Write-Host ""
    $hashOk = Verificar-Hash $destino "$($script:RutaFTPSeleccionada).sha256"

    if (-not $hashOk) {
        Write-Host ""
        $forzar = Read-Host "  Hash no coincide. Continuar de todas formas? [s/N]"
        if ($forzar -notmatch '^[sS]$') {
            Remove-Item $destino -ErrorAction SilentlyContinue
            return $false
        }
        Write-Warn "Continuando con archivo sin verificar integridad"
    }

    # Instalar segun tipo
    Write-Host ""
    Write-Info "Instalando $Servicio desde archivo local verificado..."
    switch ($Servicio) {
        "iis"    { Instalar-IIS-Desde-Marker    $destino }
        "apache" { Instalar-Apache-Desde-Marker $destino }
        "nginx"  { Instalar-Nginx-Desde-Zip     $destino }
    }
    return $true
}

# =============================================================================
# INSTALACION IIS DESDE MARKER (IIS se instala via Windows Features)
# =============================================================================

function Instalar-IIS-Desde-Marker {
    param([string]$MarkerFile)
    Write-Info "Instalando IIS via Windows Features..."
    $iis = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($iis -and $iis.Installed) {
        Write-Info "IIS ya esta instalado"
    } else {
        Install-WindowsFeature -Name Web-Server, Web-Common-Http, Web-Static-Content,
            Web-Default-Doc, Web-Http-Errors, Web-Security, Web-Filtering,
            Web-Mgmt-Tools, Web-Mgmt-Console -IncludeManagementTools | Out-Null
        Write-OK "IIS instalado"
    }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $binding = Get-WebBinding -Name "Default Web Site" | Select-Object -First 1
    if ($binding) {
        Set-WebBinding -Name "Default Web Site" `
            -BindingInformation $binding.bindingInformation `
            -PropertyName bindingInformation -Value "*:$($script:PuertoIIS):"
    }
    iisreset /restart | Out-Null
    Write-OK "IIS configurado en puerto $($script:PuertoIIS)"
}

# =============================================================================
# INSTALACION APACHE DESDE MARKER (via Chocolatey)
# =============================================================================

function Instalar-Apache-Desde-Marker {
    param([string]$MarkerFile)
    $contenido = Get-Content $MarkerFile -Raw -ErrorAction SilentlyContinue
    $version = if ($contenido -match 'choco:apache-httpd:([\d\.]+)') { $Matches[1] } else { "" }

    Write-Info "Instalando Apache $version via Chocolatey..."

    # Asegurar Chocolatey
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
        $env:Path += ";$env:ProgramData\chocolatey\bin"
    }

    choco install apache-httpd -y --no-progress 2>$null

    # Habilitar mod_headers y mod_ssl
    $apacheDir = @("C:\Apache24","$env:APPDATA\Apache24") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($apacheDir) {
        $conf = Get-Content "$apacheDir\conf\httpd.conf"
        $conf = $conf -replace '#LoadModule headers_module', 'LoadModule headers_module'
        $conf = $conf -replace '#LoadModule ssl_module',     'LoadModule ssl_module'
        $conf = $conf -replace 'Listen \d+',                 "Listen $($script:PuertoApacheHTTP)"
        $conf | Set-Content "$apacheDir\conf\httpd.conf" -Encoding UTF8
        Restart-Service Apache -ErrorAction SilentlyContinue
        Write-OK "Apache instalado y configurado en puerto $($script:PuertoApacheHTTP)"
    }
}

# =============================================================================
# INSTALACION NGINX DESDE ZIP
# =============================================================================

function Instalar-Nginx-Desde-Zip {
    param([string]$ZipFile)
    $version = if ((Split-Path $ZipFile -Leaf) -match 'nginx-([\d\.]+)\.zip') { $Matches[1] } else { "desconocida" }
    $nginxDir = "C:\nginx"

    Write-Info "Instalando Nginx $version desde ZIP..."

    if (Test-Path "$nginxDir\nginx.exe") {
        Write-Info "Nginx ya instalado en $nginxDir"
        return
    }

    Expand-Archive -Path $ZipFile -DestinationPath "C:\" -Force
    $extracted = Get-ChildItem "C:\" -Directory -Filter "nginx-*" | Select-Object -First 1
    if ($extracted) {
        if (Test-Path $nginxDir) { Remove-Item $nginxDir -Recurse -Force }
        Rename-Item $extracted.FullName $nginxDir
    }
    Remove-Item $ZipFile -ErrorAction SilentlyContinue

    if (Test-Path "$nginxDir\nginx.exe") {
        # Configurar puerto
        $conf = Get-Content "$nginxDir\conf\nginx.conf" -Raw
        $conf = $conf -replace 'listen\s+80\s*;', "listen $($script:PuertoNginxHTTP);"
        [System.IO.File]::WriteAllText("$nginxDir\conf\nginx.conf", $conf,
            [System.Text.UTF8Encoding]::new($false))

        Start-Process -FilePath "$nginxDir\nginx.exe" `
            -ArgumentList "-p `"$nginxDir`"" `
            -WorkingDirectory $nginxDir -WindowStyle Hidden
        Start-Sleep -Seconds 2

        if (Get-Process nginx -ErrorAction SilentlyContinue) {
            Write-OK "Nginx $version instalado y corriendo en puerto $($script:PuertoNginxHTTP)"
        } else {
            Write-Warn "Nginx instalado pero no inicio — verifica manualmente"
        }
    } else {
        Write-Err "No se encontro nginx.exe despues de extraer"
    }
}

# =============================================================================
# FLUJO COMPLETO: INSTALAR + SSL
# =============================================================================

function Instalar-Servicio-Completo {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   INSTALACION: $($Servicio.ToUpper())" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    Elegir-Fuente

    $ok = if ($script:FuenteInstalacion -eq "1") {
        Instalar-Web $Servicio
    } else {
        Instalar-FTP $Servicio
    }

    if (-not $ok) {
        Write-Err "Instalacion de $Servicio fallida"
        return
    }

    Write-OK "$Servicio instalado correctamente"

    # Preguntar SSL
    Write-Host ""
    $activarSSL = Read-Host "  Activar SSL/TLS en $Servicio ahora? [S/n]"
    if ($activarSSL -notmatch '^[nN]$') {
        if (-not (Validar-Cert)) {
            Write-Warn "SSL omitido (sin certificado)"
            return
        }
        switch ($Servicio) {
            "iis" {
                $ph = Read-Host "  Puerto HTTPS [443]"
                SSL-IIS -PuertoHTTP $script:PuertoIIS `
                        -PuertoHTTPS $(if ($ph) { [int]$ph } else { 443 })
            }
            "apache" {
                $ph = Read-Host "  Puerto HTTPS [453]"
                SSL-Apache -PuertoHTTP $script:PuertoApacheHTTP `
                           -PuertoHTTPS $(if ($ph) { [int]$ph } else { 453 })
            }
            "nginx" {
                $ph = Read-Host "  Puerto HTTPS [454]"
                SSL-Nginx -PuertoHTTP $script:PuertoNginxHTTP `
                          -PuertoHTTPS $(if ($ph) { [int]$ph } else { 454 })
            }
        }
    }
}

# =============================================================================
# VER ESTADO DE SERVICIOS
# =============================================================================

function Ver-Estado-Servicios {
    Write-Host ""
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   ESTADO DE SERVICIOS                    " -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # IIS
    $w3svc = Get-Service W3SVC -ErrorAction SilentlyContinue
    $col = if ($w3svc -and $w3svc.Status -eq 'Running') { "Green" } else { "Red" }
    Write-Host "  IIS (W3SVC)  : $($w3svc.Status)" -ForegroundColor $col

    # Apache
    $apache = Get-Service Apache -ErrorAction SilentlyContinue
    $col = if ($apache -and $apache.Status -eq 'Running') { "Green" } else { "Red" }
    Write-Host "  Apache       : $(if ($apache) { $apache.Status } else { 'no instalado' })" -ForegroundColor $col

    # Nginx
    $nginxProc = Get-Process nginx -ErrorAction SilentlyContinue
    $col = if ($nginxProc) { "Green" } else { "Red" }
    Write-Host "  Nginx        : $(if ($nginxProc) { 'Running' } else { 'Stopped' })" -ForegroundColor $col

    Write-Host ""
    Write-Host "  Puertos en escucha:" -ForegroundColor Cyan
    netstat -ano 2>$null | Select-String "LISTENING" |
        Select-String ":22[0-9]|:45[0-9]|:443|:21\b" |
        ForEach-Object { "    " + ($_ -replace '\s+', ' ') } |
        Select-Object -Unique

    Write-Host ""
    Write-Host "  Certificado SSL:" -ForegroundColor Cyan
    if (Cert-Existe) {
        $cert = Get-ChildItem $CERT_STORE |
                Where-Object { $_.Subject -like "*$DOMAIN*" } |
                Select-Object -First 1
        Write-OK "  Existe: $($cert.Subject)"
        Write-Info "  Expira: $($cert.NotAfter)"
    } else {
        Write-Warn "  No generado aun"
    }
    Write-Host ""
}