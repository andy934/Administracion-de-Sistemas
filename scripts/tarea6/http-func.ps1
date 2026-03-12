# =============================================================================
# http-func.ps1 - Funciones para despliegue de servidores HTTP en Windows
# Practica 6 - Administracion de Sistemas
# Sistema: Windows Server 2022
# =============================================================================

function Write-OK   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# =============================================================================
# UTILIDADES
# =============================================================================

function Crear-IndexHtml {
    param(
        [string]$Ruta,
        [string]$Titulo,
        [string]$Servidor,
        [string]$Version,
        [int]$Puerto
    )
    $lb = [char]60
    $rb = [char]62
    $html  = "${lb}!DOCTYPE html${rb}${lb}html${rb}"
    $html += "${lb}head${rb}${lb}meta charset=UTF-8${rb}${lb}title${rb}$Titulo${lb}/title${rb}${lb}/head${rb}"
    $html += "${lb}body style='font-family:Arial;text-align:center;margin-top:80px'${rb}"
    $html += "${lb}h1${rb}$Servidor${lb}/h1${rb}"
    $html += "${lb}table style='margin:auto;border-collapse:collapse;width:400px'${rb}"
    $html += "${lb}tr style='background:#1a73e8;color:white'${rb}${lb}th style='padding:10px'${rb}Campo${lb}/th${rb}${lb}th style='padding:10px'${rb}Valor${lb}/th${rb}${lb}/tr${rb}"
    $html += "${lb}tr${rb}${lb}td style='padding:8px'${rb}Servidor${lb}/td${rb}${lb}td style='padding:8px'${rb}$Servidor${lb}/td${rb}${lb}/tr${rb}"
    $html += "${lb}tr${rb}${lb}td style='padding:8px'${rb}Version${lb}/td${rb}${lb}td style='padding:8px'${rb}$Version${lb}/td${rb}${lb}/tr${rb}"
    $html += "${lb}tr${rb}${lb}td style='padding:8px'${rb}Puerto${lb}/td${rb}${lb}td style='padding:8px'${rb}$Puerto${lb}/td${rb}${lb}/tr${rb}"
    $html += "${lb}tr${rb}${lb}td style='padding:8px'${rb}Sistema${lb}/td${rb}${lb}td style='padding:8px'${rb}Windows Server 2022${lb}/td${rb}${lb}/tr${rb}"
    $html += "${lb}/table${rb}${lb}/body${rb}${lb}/html${rb}"
    Set-Content -Path $Ruta -Value $html -Encoding UTF8
}

function Validar-Entrada {
    param([string]$Valor, [string]$Nombre)
    if ([string]::IsNullOrWhiteSpace($Valor)) {
        Write-Err "El campo '$Nombre' no puede estar vacio."
        return $false
    }
    if ($Valor -match '[^a-zA-Z0-9._\-]') {
        Write-Err "El campo '$Nombre' contiene caracteres no permitidos."
        return $false
    }
    return $true
}

function Validar-Puerto {
    param([string]$Puerto)
    $puertosReservados = @(21, 22, 25, 53, 3306, 5432, 6379, 27017)
    if ($Puerto -notmatch '^\d+$') {
        Write-Err "El puerto debe ser un numero entero."
        return $false
    }
    $p = [int]$Puerto
    if ($p -lt 1 -or $p -gt 65535) {
        Write-Err "El puerto debe estar entre 1 y 65535."
        return $false
    }
    if ($puertosReservados -contains $p) {
        Write-Err "El puerto $p esta reservado para otro servicio."
        return $false
    }
    $enUso = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
    if ($enUso) {
        Write-Warn "El puerto $p ya esta en uso por otro proceso."
        return $false
    }
    return $true
}

function Configurar-Firewall {
    param([int]$Puerto)
    $puertosDefault = @(80, 8080, 8888)
    Write-Info "Configurando firewall para puerto $Puerto..."
    $reglaExiste = Get-NetFirewallRule -DisplayName "HTTP-Puerto-$Puerto" -ErrorAction SilentlyContinue
    if (-not $reglaExiste) {
        New-NetFirewallRule -DisplayName "HTTP-Puerto-$Puerto" `
            -Direction Inbound -LocalPort $Puerto `
            -Protocol TCP -Action Allow | Out-Null
    }
    foreach ($p in $puertosDefault) {
        if ($p -ne $Puerto) {
            $enUso = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
            if (-not $enUso) {
                Remove-NetFirewallRule -DisplayName "HTTP-Puerto-$p" -ErrorAction SilentlyContinue
            }
        }
    }
    Write-OK "Firewall configurado: puerto $Puerto abierto."
}

function Asegurar-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path += ";$env:ProgramData\chocolatey\bin"
        Write-OK "Chocolatey instalado."
    } else {
        Write-Info "Chocolatey ya disponible."
    }
}

# =============================================================================
# IIS
# =============================================================================

function Instalar-IIS {
    param([int]$Puerto)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   INSTALACION DE IIS                  " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $iisInstalado = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($iisInstalado -and $iisInstalado.Installed) {
        Write-Info "IIS ya esta instalado."
    } else {
        Write-Info "Instalando IIS y caracteristicas necesarias..."
        Install-WindowsFeature -Name Web-Server, Web-Common-Http, Web-Static-Content, `
            Web-Default-Doc, Web-Http-Errors, Web-Http-Logging, `
            Web-Security, Web-Filtering, Web-Stat-Compression, `
            Web-Mgmt-Tools, Web-Mgmt-Console `
            -IncludeManagementTools | Out-Null
        Write-OK "IIS instalado."
    }

    $sitio = "Default Web Site"
    Write-Info "Configurando puerto $Puerto en IIS..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $bindingActual = Get-WebBinding -Name $sitio | Select-Object -First 1
    if ($bindingActual) {
        $infoActual = $bindingActual.bindingInformation
        Set-WebBinding -Name $sitio -BindingInformation $infoActual `
            -PropertyName bindingInformation -Value "*:${Puerto}:"
    } else {
        New-WebBinding -Name $sitio -Protocol http -Port $Puerto -IPAddress "*"
    }
    Write-OK "Puerto IIS configurado: $Puerto"

    Configurar-Seguridad-IIS

    $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $version) { $version = "10.0" }

    $wwwroot = "C:\inetpub\wwwroot"
    Crear-IndexHtml -Ruta "$wwwroot\index.html" -Titulo "IIS" -Servidor "IIS" -Version $version -Puerto $Puerto

    Configurar-Firewall -Puerto $Puerto

    iisreset /restart | Out-Null

    if ((Get-Service W3SVC).Status -eq 'Running') {
        Write-OK "IIS corriendo en puerto $Puerto."
        Write-Host ""
        Write-Host "Verificacion con curl:" -ForegroundColor Green
        try {
            $respuesta = Invoke-WebRequest -Uri "http://localhost:$Puerto" -Method Head -UseBasicParsing
            Write-Host "HTTP $($respuesta.StatusCode) $($respuesta.StatusDescription)"
            $respuesta.Headers.GetEnumerator() | Select-Object -First 6 |
                ForEach-Object { Write-Host "$($_.Key): $($_.Value)" }
        } catch {
            Write-Warn "No se pudo verificar. Prueba: curl -I http://IP:$Puerto"
        }
    } else {
        Write-Err "IIS no pudo iniciarse."
    }
}

function Configurar-Seguridad-IIS {
    Write-Info "Configurando seguridad IIS..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    try {
        Remove-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name='X-Powered-By'} -ErrorAction SilentlyContinue
    } catch { }

    try {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
    } catch { }

    $headers = @(
        @{ name = "X-Frame-Options";        value = "SAMEORIGIN" },
        @{ name = "X-Content-Type-Options"; value = "nosniff" },
        @{ name = "X-XSS-Protection";       value = "1; mode=block" }
    )
    foreach ($h in $headers) {
        try {
            Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -Value $h -ErrorAction SilentlyContinue
        } catch { }
    }

    $webConfig = "C:\inetpub\wwwroot\web.config"
    if (-not (Test-Path $webConfig)) {
        $lb = [char]60
        $rb = [char]62
        $xmlLines = @(
            "${lb}?xml version=`"1.0`" encoding=`"UTF-8`"?${rb}",
            "${lb}configuration${rb}",
            "  ${lb}system.webServer${rb}",
            "    ${lb}security${rb}",
            "      ${lb}requestFiltering${rb}",
            "        ${lb}verbs allowUnlisted=`"false`"${rb}",
            "          ${lb}add verb=`"GET`" allowed=`"true`" /${rb}",
            "          ${lb}add verb=`"POST`" allowed=`"true`" /${rb}",
            "          ${lb}add verb=`"HEAD`" allowed=`"true`" /${rb}",
            "          ${lb}add verb=`"OPTIONS`" allowed=`"true`" /${rb}",
            "        ${lb}/verbs${rb}",
            "      ${lb}/requestFiltering${rb}",
            "    ${lb}/security${rb}",
            "  ${lb}/system.webServer${rb}",
            "${lb}/configuration${rb}"
        )
        Set-Content -Path $webConfig -Value $xmlLines -Encoding UTF8
    }

    Write-OK "Seguridad IIS configurada."
}

# =============================================================================
# APACHE (Windows) - via Chocolatey
# =============================================================================

function Listar-Versiones-Apache-Win {
    Write-Host ""
    Write-Info "Consultando versiones disponibles de Apache HTTP Server..."
    Write-Host ""

    $script:ApacheVersiones = @()

    Asegurar-Chocolatey
    try {
        # Choco v2: search devuelve "apache-httpd 2.4.55 [Approved]"
        $searchResult = choco search apache-httpd --exact 2>$null
        $version = $searchResult |
                   Where-Object { $_ -match '^apache-httpd\s+[\d\.]+' } |
                   ForEach-Object { if ($_ -match '^apache-httpd\s+([\d\.]+)') { $Matches[1] } } |
                   Select-Object -First 1

        if ($version -and $version -match '^\d+\.\d+\.\d+') {
            $script:ApacheVersiones = @($version, $version, $version)
        }
    } catch { }

    if ($script:ApacheVersiones.Count -eq 0) {
        try {
            $versWinget = winget show Apache.HTTPServer --versions 2>$null |
                          Where-Object { $_ -match '^\d+\.\d+\.\d+' } |
                          Sort-Object { [version]$_ }
            if ($versWinget -and $versWinget.Count -ge 1) {
                $last = $versWinget | Select-Object -Last 1
                $prev = if ($versWinget.Count -ge 2) { $versWinget | Select-Object -Last 2 | Select-Object -First 1 } else { $last }
                $script:ApacheVersiones = @($prev, $last, $last)
            }
        } catch { }
    }

    if ($script:ApacheVersiones.Count -eq 0) {
        Write-Warn "No se pudieron consultar versiones. Usando versiones conocidas."
        $script:ApacheVersiones = @("2.4.62", "2.4.63", "2.4.63")
    }

    $etiquetas = @("Estable anterior", "Estable actual (LTS)", "Desarrollo (Latest)")
    Write-Host "  Versiones disponibles (Apache HTTP Server):" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $script:ApacheVersiones.Count; $i++) {
        Write-Host "    $($i+1). $($script:ApacheVersiones[$i]) - $($etiquetas[$i])"
    }
    Write-Host ""
}

function Instalar-Apache-Win {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   INSTALACION DE APACHE HTTP SERVER   " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Listar-Versiones-Apache-Win

    $total = $script:ApacheVersiones.Count
    $seleccion = 0
    do {
        $inp = Read-Host "Seleccione numero de version (1-$total)"
        if ($inp -match '^\d+$' -and [int]$inp -ge 1 -and [int]$inp -le $total) {
            $seleccion = [int]$inp
        } else {
            Write-Err "Seleccion invalida."
        }
    } while ($seleccion -eq 0)

    $versionElegida = $script:ApacheVersiones[$seleccion - 1]

    $puerto = ""
    do {
        $inp = Read-Host "Puerto de escucha (ej. 80, 8080, 8888)"
        if (Validar-Puerto -Puerto $inp) { $puerto = $inp }
    } while ([string]::IsNullOrEmpty($puerto))
    $puertoNum = [int]$puerto

    Stop-Service "Apache*" -ErrorAction SilentlyContinue

    Write-Info "Instalando Apache HTTP Server $versionElegida via Chocolatey..."
    Asegurar-Chocolatey

    choco install apache-httpd --version $versionElegida -y --no-progress 2>$null
    if ($LASTEXITCODE -ne 0) {
        choco install apache-httpd -y --no-progress 2>$null
    }

    # Chocolatey instala apache en AppData\Roaming\Apache24 por defecto
    $posiblesRutas = @(
        "C:\Apache24",
        "C:\Program Files\Apache Software Foundation\Apache2.4",
        "$env:APPDATA\Apache24",
        "$env:APPDATA\httpd-*",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24"
    )
    $apacheDir = $posiblesRutas | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $apacheDir) {
        # Buscar donde choco lo extrae
        $apacheDir = Get-ChildItem "$env:APPDATA" -Directory -Filter "Apache*" -ErrorAction SilentlyContinue |
                     Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $apacheDir) {
        $apacheDir = Get-ChildItem "C:\ProgramData\chocolatey\lib\apache-httpd\tools" `
                     -Directory -Filter "Apache*" -ErrorAction SilentlyContinue |
                     Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $apacheDir) {
        Write-Err "No se encontro el directorio de instalacion de Apache."
        return
    }

    Write-OK "Apache instalado en $apacheDir"

    $httpdConf = "$apacheDir\conf\httpd.conf"
    if (Test-Path $httpdConf) {
        $conf = Get-Content $httpdConf
        # Cambiar puerto
        $conf = $conf -replace 'Listen \d+', "Listen $puertoNum"
        # Habilitar mod_headers (requerido para Header always set ...)
        $conf = $conf -replace '#LoadModule headers_module', 'LoadModule headers_module'
        # Habilitar mod_rewrite por si acaso
        $conf = $conf -replace '#LoadModule rewrite_module', 'LoadModule rewrite_module'
        $conf | Set-Content $httpdConf
        Write-OK "Puerto configurado: $puertoNum"
    }

    $secConf = "$apacheDir\conf\extra\httpd-security.conf"
    $secLines = @(
        'ServerTokens Prod',
        'ServerSignature Off',
        '',
        'Header always set X-Frame-Options SAMEORIGIN',
        'Header always set X-Content-Type-Options nosniff',
        'Header always set X-XSS-Protection "1; mode=block"',
        'Header always unset X-Powered-By',
        '',
        '<Location />',
        '    <LimitExcept GET POST HEAD OPTIONS>',
        '        Require all denied',
        '    </LimitExcept>',
        '</Location>'
    )
    Set-Content -Path $secConf -Value $secLines -Encoding UTF8

    if ((Get-Content $httpdConf) -notmatch 'httpd-security') {
        Add-Content $httpdConf "`nInclude conf/extra/httpd-security.conf"
    }

    Crear-IndexHtml -Ruta "$apacheDir\htdocs\index.html" -Titulo "Apache" -Servidor "Apache HTTP Server" -Version $versionElegida -Puerto $puertoNum

    Configurar-Firewall -Puerto $puertoNum

    if (Test-Path "$apacheDir\bin\httpd.exe") {
        # Verificar si el servicio Apache ya existe (chocolatey lo instala como "Apache")
        $svcExistente = Get-Service "Apache" -ErrorAction SilentlyContinue
        if ($svcExistente) {
            $nombreServicio = "Apache"
        } else {
            & "$apacheDir\bin\httpd.exe" -k install -n "Apache$puertoNum" 2>$null
            $nombreServicio = "Apache$puertoNum"
        }

        # Iniciar servicio
        $svcAntes = Get-Service $nombreServicio -ErrorAction SilentlyContinue
        if ($svcAntes -and $svcAntes.Status -eq 'Running') {
            Stop-Service $nombreServicio -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Start-Service $nombreServicio -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        # Verificar proceso httpd.exe directamente (mas confiable que el servicio)
        $httpdProc = Get-Process httpd -ErrorAction SilentlyContinue
        $svcDespues = Get-Service $nombreServicio -ErrorAction SilentlyContinue

        if ($httpdProc -or ($svcDespues -and $svcDespues.Status -eq 'Running')) {
            Write-OK "Apache corriendo en puerto $puertoNum. (servicio: $nombreServicio)"
            Write-Host ""
            Write-Host "Verificacion con curl:" -ForegroundColor Green
            curl.exe -sI "http://localhost:$puertoNum" 2>$null | Select-Object -First 6
        } else {
            # Intentar arrancar httpd.exe directamente como fallback
            Write-Warn "Servicio no arranco, intentando arranque directo..."
            Start-Process -FilePath "$apacheDir\bin\httpd.exe" -WindowStyle Hidden
            Start-Sleep -Seconds 3
            $httpdProc = Get-Process httpd -ErrorAction SilentlyContinue
            if ($httpdProc) {
                Write-OK "Apache corriendo en puerto $puertoNum (proceso directo)."
                curl.exe -sI "http://localhost:$puertoNum" 2>$null | Select-Object -First 6
            } else {
                Write-Err "Apache no pudo iniciarse. Revisa $apacheDir\logs\error.log"
            }
        }
    }
}

# =============================================================================
# NGINX (Windows) - via Chocolatey
# =============================================================================

function Listar-Versiones-Nginx-Win {
    Write-Host ""
    Write-Info "Consultando versiones disponibles de Nginx..."
    Write-Host ""

    $script:NginxVersiones = @()

    try {
        # Consultar versiones directamente desde nginx.org
        $html = (New-Object System.Net.WebClient).DownloadString('https://nginx.org/en/download.html')
        $matches_stable  = [regex]::Matches($html, 'nginx-(1\.\d*[02468]\.\d+)\.zip')
        $matches_mainline = [regex]::Matches($html, 'nginx-(1\.\d*[13579]\.\d+)\.zip')

        $stable = $matches_stable | ForEach-Object { $_.Groups[1].Value } |
                  Sort-Object { [version]$_ } | Select-Object -Unique
        $mainline = $matches_mainline | ForEach-Object { $_.Groups[1].Value } |
                    Sort-Object { [version]$_ } | Select-Object -Unique | Select-Object -Last 1

        if ($stable -and $stable.Count -ge 2) {
            $s = @($stable)
            $script:NginxVersiones = @(
                $s[$s.Count - 2],
                $s[$s.Count - 1],
                $(if ($mainline) { $mainline } else { $s[$s.Count - 1] })
            )
        } elseif ($stable -and $stable.Count -eq 1) {
            $script:NginxVersiones = @($stable[0], $stable[0], $(if ($mainline) { $mainline } else { $stable[0] }))
        }
    } catch { }

    if ($script:NginxVersiones.Count -eq 0) {
        Write-Warn "No se pudieron consultar versiones. Usando versiones conocidas."
        $script:NginxVersiones = @("1.26.3", "1.28.0", "1.27.4")
    }

    $etiquetas = @("Estable anterior", "Estable actual", "Desarrollo (Mainline)")
    Write-Host "  Versiones disponibles (Nginx):" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $script:NginxVersiones.Count; $i++) {
        Write-Host "    $($i+1). $($script:NginxVersiones[$i]) - $($etiquetas[$i])"
    }
    Write-Host ""
}

function Instalar-Nginx-Win {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   INSTALACION DE NGINX                " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Listar-Versiones-Nginx-Win

    $total = $script:NginxVersiones.Count
    $seleccion = 0
    do {
        $inp = Read-Host "Seleccione numero de version (1-$total)"
        if ($inp -match '^\d+$' -and [int]$inp -ge 1 -and [int]$inp -le $total) {
            $seleccion = [int]$inp
        } else {
            Write-Err "Seleccion invalida."
        }
    } while ($seleccion -eq 0)

    $versionElegida = $script:NginxVersiones[$seleccion - 1]

    $puerto = ""
    do {
        $inp = Read-Host "Puerto de escucha (ej. 80, 8080, 8888)"
        if (Validar-Puerto -Puerto $inp) { $puerto = $inp }
    } while ([string]::IsNullOrEmpty($puerto))
    $puertoNum = [int]$puerto

    Stop-Service "nginx" -ErrorAction SilentlyContinue
    taskkill /f /im nginx.exe 2>$null

    # Descargar e instalar nginx directamente desde nginx.org
    $nginxDir = "C:\nginx"
    $zipPath  = "$env:TEMP\nginx-$versionElegida.zip"

    if (Test-Path "$nginxDir\nginx.exe") {
        Write-Info "Nginx ya instalado en $nginxDir"
    } else {
        Write-Info "Descargando Nginx $versionElegida desde nginx.org..."
        $url = "https://nginx.org/download/nginx-$versionElegida.zip"
        try {
            (New-Object System.Net.WebClient).DownloadFile($url, $zipPath)
            Write-Info "Extrayendo..."
            Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force
            # El zip extrae a C:\nginx-x.x.x, renombrar a C:\nginx
            $extracted = Get-ChildItem "C:\" -Directory -Filter "nginx-*" | Select-Object -First 1
            if ($extracted) {
                if (Test-Path $nginxDir) { Remove-Item $nginxDir -Recurse -Force }
                Rename-Item $extracted.FullName $nginxDir
            }
            Remove-Item $zipPath -ErrorAction SilentlyContinue
            Write-OK "Nginx instalado en $nginxDir"
        } catch {
            Write-Err "Error descargando Nginx: $_"
            return
        }
    }

    if (-not (Test-Path "$nginxDir\nginx.exe")) {
        Write-Err "No se encontro nginx.exe en $nginxDir"
        return
    }

    Write-OK "Nginx instalado en $nginxDir"

    $nginxConf = "$nginxDir\conf\nginx.conf"
    if (Test-Path $nginxConf) {
        $confLines = @(
            'worker_processes  auto;',
            '',
            'events {',
            '    worker_connections  1024;',
            '}',
            '',
            'http {',
            '    server_tokens off;',
            '    add_header X-Frame-Options SAMEORIGIN always;',
            '    add_header X-Content-Type-Options nosniff always;',
            '    add_header X-XSS-Protection "1; mode=block" always;',
            '    include       mime.types;',
            '    default_type  application/octet-stream;',
            '    server {',
            "        listen       $puertoNum;",
            '        server_name  localhost;',
            '        root         html;',
            '        index        index.html index.htm;',
            '        location / {',
            '            try_files $uri $uri/ =404;',
            '        }',
            '    }',
            '}'
        )
        # nginx no acepta BOM - usar ASCII o UTF8 sin BOM
        $confText = $confLines -join "`r`n"
        [System.IO.File]::WriteAllText($nginxConf, $confText, [System.Text.UTF8Encoding]::new($false))
        Write-OK "Puerto configurado: $puertoNum"
    }

    Crear-IndexHtml -Ruta "$nginxDir\html\index.html" -Titulo "Nginx" -Servidor "Nginx" -Version $versionElegida -Puerto $puertoNum

    Configurar-Firewall -Puerto $puertoNum

    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    $nssmPath = if ($nssmCmd) { $nssmCmd.Source } else { $null }

    # Matar instancia previa si existe
    taskkill /f /im nginx.exe 2>$null | Out-Null
    Start-Sleep -Seconds 1

    # Instalar como servicio con NSSM si esta disponible
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) {
        $svcName = "nginx-$puertoNum"
        nssm install $svcName "$nginxDir
ginx.exe" 2>$null
        nssm set $svcName AppDirectory $nginxDir 2>$null
        nssm set $svcName AppParameters "-p `"$nginxDir`"" 2>$null
        Start-Service $svcName -ErrorAction SilentlyContinue
    }

    # Siempre arrancar proceso directo (funciona aunque no haya NSSM)
    Start-Process -FilePath "$nginxDir
ginx.exe" `
        -ArgumentList "-p `"$nginxDir`"" `
        -WorkingDirectory $nginxDir `
        -WindowStyle Hidden

    Start-Sleep -Seconds 2

    $nginxProc = Get-Process nginx -ErrorAction SilentlyContinue
    if ($nginxProc) {
        Write-OK "Nginx corriendo en puerto $puertoNum."
        Write-Host ""
        Write-Host "Verificacion con curl:" -ForegroundColor Green
        curl.exe -sI "http://localhost:$puertoNum" 2>$null | Select-Object -First 6
    } else {
        Write-Err "Nginx no pudo iniciarse. Revisa $nginxDir\logs\error.log"
    }
}

# =============================================================================
# GESTION DE SERVICIOS
# =============================================================================

function Ver-Estado-Servicios {
    Write-Host ""
    Write-Host "=== ESTADO DE SERVICIOS HTTP ===" -ForegroundColor Cyan
    Write-Host ""

    $w3svc = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($w3svc) {
        $estado = if ($w3svc.Status -eq 'Running') { "[ACTIVO]" } else { "[INACTIVO]" }
        $color  = if ($w3svc.Status -eq 'Running') { "Green" } else { "Red" }
        Write-Host "  IIS        " -NoNewline; Write-Host $estado -ForegroundColor $color
    }

    $apache = Get-Service "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($apache) {
        $estado = if ($apache.Status -eq 'Running') { "[ACTIVO]" } else { "[INACTIVO]" }
        $color  = if ($apache.Status -eq 'Running') { "Green" } else { "Red" }
        Write-Host "  Apache     " -NoNewline; Write-Host $estado -ForegroundColor $color
    }

    $nginxProc = Get-Process nginx -ErrorAction SilentlyContinue
    if ($nginxProc) {
        Write-Host "  Nginx      " -NoNewline; Write-Host "[ACTIVO]" -ForegroundColor Green
    }

    Write-Host ""
}

function Cambiar-Puerto-Servicio {
    Write-Host ""
    Write-Host "=== CAMBIAR PUERTO ===" -ForegroundColor Cyan
    Write-Host "  1. IIS"
    Write-Host "  2. Apache"
    Write-Host "  3. Nginx"
    Write-Host ""
    $opcion = Read-Host "Seleccione servicio (1-3)"

    $nuevoPuerto = ""
    do {
        $inp = Read-Host "Nuevo puerto"
        if (Validar-Puerto -Puerto $inp) { $nuevoPuerto = $inp }
    } while ([string]::IsNullOrEmpty($nuevoPuerto))
    $puertoNum = [int]$nuevoPuerto

    switch ($opcion) {
        "1" {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            $binding = Get-WebBinding -Name "Default Web Site" | Select-Object -First 1
            if ($binding) {
                Set-WebBinding -Name "Default Web Site" `
                    -BindingInformation $binding.bindingInformation `
                    -PropertyName bindingInformation -Value "*:${puertoNum}:"
            }
            Configurar-Firewall -Puerto $puertoNum
            iisreset /restart | Out-Null
            Write-OK "IIS reiniciado en puerto $puertoNum"
        }
        "2" {
            $apacheDir = @("C:\Apache24", "C:\Program Files\Apache Software Foundation\Apache2.4",
                              "$env:APPDATA\Apache24") |
                         Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($apacheDir) {
                (Get-Content "$apacheDir\conf\httpd.conf") -replace 'Listen \d+', "Listen $puertoNum" |
                    Set-Content "$apacheDir\conf\httpd.conf"
                Configurar-Firewall -Puerto $puertoNum
                Restart-Service "Apache*" -ErrorAction SilentlyContinue
                Write-OK "Apache reiniciado en puerto $puertoNum"
            }
        }
        "3" {
            $nginxDir = @("C:\nginx") + (Get-ChildItem "C:\ProgramData\chocolatey\lib\nginx\tools" `
                -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) |
                Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($nginxDir) {
                (Get-Content "$nginxDir\conf\nginx.conf") -replace 'listen\s+\d+', "listen $puertoNum" |
                    Set-Content "$nginxDir\conf\nginx.conf"
                Configurar-Firewall -Puerto $puertoNum
                taskkill /f /im nginx.exe 2>$null
                Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
                Write-OK "Nginx reiniciado en puerto $puertoNum"
            }
        }
        default { Write-Err "Opcion invalida." }
    }
}

function Ver-Logs-Servicio {
    Write-Host "  1. IIS"
    Write-Host "  2. Apache"
    Write-Host "  3. Nginx"
    $opcion = Read-Host "Seleccione servicio (1-3)"

    switch ($opcion) {
        "1" {
            $logDir = "C:\inetpub\logs\LogFiles"
            $logFile = Get-ChildItem $logDir -Recurse -Filter "*.log" -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($logFile) { Get-Content $logFile.FullName -Tail 20 }
        }
        "2" {
            $apacheDir = @("C:\Apache24", "C:\Program Files\Apache Software Foundation\Apache2.4",
                              "$env:APPDATA\Apache24") |
                         Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($apacheDir) { Get-Content "$apacheDir\logs\error.log" -Tail 20 -ErrorAction SilentlyContinue }
        }
        "3" {
            $nginxDir = "C:\nginx"
            if (Test-Path $nginxDir) { Get-Content "$nginxDir\logs\error.log" -Tail 20 -ErrorAction SilentlyContinue }
        }
        default { Write-Err "Opcion invalida." }
    }
}

function Desinstalar-Servicio {
    Write-Host "  1. IIS"
    Write-Host "  2. Apache"
    Write-Host "  3. Nginx"
    $opcion = Read-Host "Seleccione servicio a desinstalar (1-3)"
    $confirm = Read-Host "Esta seguro? (s/n)"
    if ($confirm -ne 's' -and $confirm -ne 'S') { return }

    switch ($opcion) {
        "1" {
            Uninstall-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
            Write-OK "IIS desinstalado."
        }
        "2" {
            Stop-Service "Apache*" -ErrorAction SilentlyContinue
            $apacheDir = @("C:\Apache24") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($apacheDir) { & "$apacheDir\bin\httpd.exe" -k uninstall 2>$null }
            choco uninstall apache-httpd -y 2>$null
            Write-OK "Apache desinstalado."
        }
        "3" {
            taskkill /f /im nginx.exe 2>$null
            choco uninstall nginx -y 2>$null
            Write-OK "Nginx desinstalado."
        }
        default { Write-Err "Opcion invalida." }
    }
}