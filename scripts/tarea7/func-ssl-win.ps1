?# =============================================================================
# func-ssl-win.ps1 - SSL/TLS para Windows Server 2022
# Practica 7 - Administracion de Sistemas
# =============================================================================

$SSL_DIR    = "C:\ssl\tarea7"
$DOMAIN     = "reprobados.com"
$CERT_PATH  = "$SSL_DIR\reprobados.crt"
$KEY_PATH   = "$SSL_DIR\reprobados.key"
$PFX_PATH   = "$SSL_DIR\reprobados.pfx"
$PFX_PASS   = "tarea7ssl"
$CERT_STORE = "Cert:\LocalMachine\My"
$DAYS       = 365

# Buscar openssl de Apache si no esta en PATH
function Get-OpenSSL {
    $ossl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($ossl) { return $ossl.Source }
    $apacheDir = @("C:\Apache24","$env:APPDATA\Apache24") |
                 Where-Object { Test-Path "$_\bin\openssl.exe" } | Select-Object -First 1
    if ($apacheDir) { return "$apacheDir\bin\openssl.exe" }
    return $null
}

function Cert-Existe {
    return (Test-Path $PFX_PATH) -and
           ($null -ne (Get-ChildItem $CERT_STORE -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -like "*$DOMAIN*" }))
}

function Validar-Cert {
    if (Cert-Existe) { return $true }
    Write-Warn "No existe certificado SSL para $DOMAIN"
    $r = Read-Host "  Generar certificado ahora? [S/n]"
    if ($r -match '^[nN]$') { return $false }
    Generar-Certificado
    return (Cert-Existe)
}

function Get-CertThumbprint {
    $cert = Get-ChildItem $CERT_STORE -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -like "*$DOMAIN*" } |
            Sort-Object NotAfter -Descending | Select-Object -First 1
    return $cert.Thumbprint
}

# =============================================================================
# GENERAR CERTIFICADO
# =============================================================================

function Generar-Certificado {
    Write-Info "Generando certificado SSL autofirmado para $DOMAIN..."
    New-Item -ItemType Directory -Force -Path $SSL_DIR | Out-Null

    $existing = Get-ChildItem $CERT_STORE -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -like "*$DOMAIN*" }
    if ($existing) {
        Write-Warn "Certificado ya existe en el store"
        $r = Read-Host "  Regenerar? [s/N]"
        if ($r -notmatch '^[sS]$') {
            Write-OK "Usando certificado existente"
            if (-not (Test-Path $PFX_PATH)) {
                $pass = ConvertTo-SecureString $PFX_PASS -AsPlainText -Force
                Export-PfxCertificate -Cert $existing[0] -FilePath $PFX_PATH -Password $pass | Out-Null
                Write-OK "PFX exportado: $PFX_PATH"
            }
            # Exportar PEM si no existe
            Exportar-PEM
            return
        }
        $existing | Remove-Item -ErrorAction SilentlyContinue
    }

    $cert = New-SelfSignedCertificate `
        -DnsName $DOMAIN, "www.$DOMAIN", "localhost" `
        -CertStoreLocation $CERT_STORE `
        -NotAfter (Get-Date).AddDays($DAYS) `
        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") `
        -FriendlyName "Tarea7-$DOMAIN"

    if (-not $cert) { Write-Err "Fallo la generacion del certificado"; return }

    $pass = ConvertTo-SecureString $PFX_PASS -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $PFX_PATH -Password $pass | Out-Null
    Export-Certificate -Cert $cert -FilePath "$SSL_DIR\reprobados-der.crt" -Type CERT | Out-Null

    # Agregar a Trusted Root
    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
    $rootStore.Open("ReadWrite")
    $rootStore.Add($cert)
    $rootStore.Close()

    Write-OK "Certificado generado:"
    Write-OK "  Thumbprint : $($cert.Thumbprint)"
    Write-OK "  Subject    : $($cert.Subject)"
    Write-OK "  Expira     : $($cert.NotAfter)"
    Write-OK "  PFX        : $PFX_PATH"

    # Exportar PEM para Apache/Nginx
    Exportar-PEM
}

function Exportar-PEM {
    $ossl = Get-OpenSSL
    if (-not $ossl) {
        Write-Warn "openssl no encontrado - archivos PEM no exportados"
        Write-Warn "Apache y Nginx necesitan PEM. Instala openssl o usa el de Apache."
        return
    }
    & $ossl pkcs12 -in $PFX_PATH -clcerts -nokeys -passin "pass:$PFX_PASS" `
        -out $CERT_PATH 2>$null
    & $ossl pkcs12 -in $PFX_PATH -nocerts -nodes -passin "pass:$PFX_PASS" `
        -out $KEY_PATH 2>$null
    if ((Test-Path $CERT_PATH) -and (Test-Path $KEY_PATH)) {
        Write-OK "Archivos PEM exportados: $CERT_PATH / $KEY_PATH"
    } else {
        Write-Warn "No se pudieron exportar archivos PEM"
    }
}

# =============================================================================
# SSL PARA IIS
# =============================================================================

function SSL-IIS {
    param([int]$PuertoHTTP = 222, [int]$PuertoHTTPS = 443)
    if (-not (Validar-Cert)) { return }

    Write-Info "Configurando SSL en IIS (HTTP:$PuertoHTTP -> HTTPS:$PuertoHTTPS)..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $sitio = "Default Web Site"
    $thumb  = Get-CertThumbprint
    if (-not $thumb) { Write-Err "No se encontro thumbprint"; return }

    $bindingExiste = Get-WebBinding -Name $sitio -Protocol https -ErrorAction SilentlyContinue |
                     Where-Object { $_.bindingInformation -like "*:${PuertoHTTPS}:*" }
    if (-not $bindingExiste) {
        New-WebBinding -Name $sitio -Protocol https -Port $PuertoHTTPS -IPAddress "*"
        Write-OK "Binding HTTPS agregado en puerto $PuertoHTTPS"
    } else {
        Write-Info "Binding HTTPS ya existe"
    }

    try {
        $binding = Get-WebBinding -Name $sitio -Protocol https -Port $PuertoHTTPS
        $binding.AddSslCertificate($thumb, "My")
        Write-OK "Certificado asignado al binding HTTPS"
    } catch {
        Write-Warn "Certificado ya asignado o error: $_"
    }

    # Cabeceras de seguridad via web.config (sin URL Rewrite)
    $wwwroot    = "C:\inetpub\wwwroot"
    $webConfig  = "$wwwroot\web.config"
    $wcContent  = '<?xml version="1.0" encoding="UTF-8"?>'
    $wcContent += '<configuration><system.webServer>'
    $wcContent += '<httpProtocol><customHeaders>'
    $wcContent += '<add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />'
    $wcContent += '<add name="X-Frame-Options" value="SAMEORIGIN" />'
    $wcContent += '<add name="X-Content-Type-Options" value="nosniff" />'
    $wcContent += '</customHeaders></httpProtocol>'
    $wcContent += '<security><requestFiltering removeServerHeader="true" /></security>'
    $wcContent += '</system.webServer></configuration>'
    [System.IO.File]::WriteAllText($webConfig, $wcContent, [System.Text.UTF8Encoding]::new($false))
    Write-OK "Cabeceras de seguridad configuradas"

    iisreset /restart 2>$null | Out-Null
    Start-Sleep -Seconds 3
    # Abrir puertos en firewall de Windows
    New-NetFirewallRule -DisplayName "HTTPS-Puerto-$PuertoHTTPS" -Direction Inbound -LocalPort $PuertoHTTPS -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "HTTP-Puerto-$PuertoHTTP" -Direction Inbound -LocalPort $PuertoHTTP -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    if ((Get-Service W3SVC).Status -eq 'Running') {
        Write-OK "IIS SSL habilitado en puerto $PuertoHTTPS"
    } else {
        Write-Err "IIS no pudo reiniciarse"
    }
}

# =============================================================================
# SSL PARA APACHE
# =============================================================================

function SSL-Apache {
    param([int]$PuertoHTTP = 223, [int]$PuertoHTTPS = 453)
    if (-not (Validar-Cert)) { return }

    $apacheDir = @("C:\Apache24","C:\Program Files\Apache Software Foundation\Apache2.4",
                   "$env:APPDATA\Apache24") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $apacheDir) { Write-Err "Apache no encontrado"; return }

    Write-Info "Configurando SSL en Apache ($apacheDir)..."
    Write-Info "  HTTP:$PuertoHTTP -> HTTPS:$PuertoHTTPS"

    # Exportar PEM si no existe
    if (-not (Test-Path $CERT_PATH) -or -not (Test-Path $KEY_PATH)) {
        Exportar-PEM
    }
    if (-not (Test-Path $CERT_PATH) -or -not (Test-Path $KEY_PATH)) {
        Write-Err "Archivos PEM no disponibles - SSL no puede configurarse"
        return
    }

    $httpdConf = "$apacheDir\conf\httpd.conf"
    $extraDir  = "$apacheDir\conf\extra"

    # Comentar httpd-ahssl.conf para evitar conflictos
    $conf = Get-Content $httpdConf
    $conf = $conf -replace '^Include conf/extra/httpd-ahssl.conf', '#Include conf/extra/httpd-ahssl.conf'
    $conf = $conf -replace '#LoadModule ssl_module',           'LoadModule ssl_module'
    $conf = $conf -replace '#LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $conf = $conf -replace '#LoadModule rewrite_module',       'LoadModule rewrite_module'
    $conf = $conf -replace '#LoadModule headers_module',       'LoadModule headers_module'

    if (-not ($conf -match "Listen $PuertoHTTPS")) { $conf += "Listen $PuertoHTTPS" }
    if (-not ($conf -match "httpd-ssl-tarea7.conf"))    { $conf += "Include conf/extra/httpd-ssl-tarea7.conf" }
    if (-not ($conf -match "httpd-redirect-tarea7.conf")) { $conf += "Include conf/extra/httpd-redirect-tarea7.conf" }
    [System.IO.File]::WriteAllLines($httpdConf, $conf, [System.Text.UTF8Encoding]::new($false))

    $certFwd = $CERT_PATH -replace '\\','/'
    $keyFwd  = $KEY_PATH  -replace '\\','/'
    $docRoot = ($apacheDir -replace '\\','/') + "/htdocs"

    $sslConf = @(
        "# VirtualHost HTTPS - Practica 7",
        "<VirtualHost *:$PuertoHTTPS>",
        "    ServerName $DOMAIN",
        "    ServerAlias www.$DOMAIN",
        "    SSLEngine on",
        "    SSLCertificateFile    `"$certFwd`"",
        "    SSLCertificateKeyFile `"$keyFwd`"",
        "    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1",
        "    SSLCipherSuite        HIGH:!aNULL:!MD5:!3DES",
        "    DocumentRoot `"$docRoot`"",
        "    Header always set Strict-Transport-Security `"max-age=31536000`"",
        "    Header always set X-Frame-Options `"SAMEORIGIN`"",
        "    Header always set X-Content-Type-Options `"nosniff`"",
        "</VirtualHost>"
    )
    [System.IO.File]::WriteAllLines("$extraDir\httpd-ssl-tarea7.conf",
        $sslConf, [System.Text.UTF8Encoding]::new($false))

    $redirConf = @(
        "# Redireccion HTTP -> HTTPS - Practica 7",
        "<VirtualHost *:$PuertoHTTP>",
        "    ServerName $DOMAIN",
        "    RewriteEngine On",
        "    RewriteRule ^(.*)$ https://%{HTTP_HOST}`$1 [R=301,L]",
        "</VirtualHost>"
    )
    [System.IO.File]::WriteAllLines("$extraDir\httpd-redirect-tarea7.conf",
        $redirConf, [System.Text.UTF8Encoding]::new($false))

    $test = & "$apacheDir\bin\httpd.exe" -t 2>&1
    if ($test -match "Syntax OK") {
        Restart-Service Apache -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Abrir puertos en firewall de Windows
        New-NetFirewallRule -DisplayName "HTTPS-Puerto-$PuertoHTTPS" -Direction Inbound -LocalPort $PuertoHTTPS -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "HTTP-Puerto-$PuertoHTTP" -Direction Inbound -LocalPort $PuertoHTTP -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-OK "Apache SSL habilitado en puerto $PuertoHTTPS"
        Write-OK "  Redireccion activa: $PuertoHTTP -> $PuertoHTTPS"
    } else {
        Write-Err "Error en configuracion Apache:"
        $test | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" }
    }
}

# =============================================================================
# SSL PARA NGINX
# =============================================================================

function SSL-Nginx {
    param([int]$PuertoHTTP = 204, [int]$PuertoHTTPS = 454)
    if (-not (Validar-Cert)) { return }

    $nginxDir = "C:\nginx"
    if (-not (Test-Path "$nginxDir\nginx.exe")) {
        Write-Err "Nginx no encontrado en $nginxDir"
        return
    }

    Write-Info "Configurando SSL en Nginx (HTTP:$PuertoHTTP -> HTTPS:$PuertoHTTPS)..."

    # Exportar PEM si no existe
    if (-not (Test-Path $CERT_PATH) -or -not (Test-Path $KEY_PATH)) {
        Exportar-PEM
    }
    if (-not (Test-Path $CERT_PATH) -or -not (Test-Path $KEY_PATH)) {
        Write-Err "Archivos PEM no disponibles - SSL no puede configurarse"
        return
    }

    $certFwd = $CERT_PATH -replace '\\','/'
    $keyFwd  = $KEY_PATH  -replace '\\','/'

    $nginxConf = @(
        "worker_processes  auto;",
        "error_log  logs/error.log warn;",
        "pid        logs/nginx.pid;",
        "events { worker_connections 1024; }",
        "http {",
        "    include       mime.types;",
        "    default_type  application/octet-stream;",
        "    server_tokens off;",
        "    server {",
        "        listen $PuertoHTTP;",
        "        server_name $DOMAIN www.$DOMAIN;",
        "        return 301 https://`$host`$request_uri;",
        "    }",
        "    server {",
        "        listen $PuertoHTTPS ssl;",
        "        server_name $DOMAIN www.$DOMAIN;",
        "        ssl_certificate     `"$certFwd`";",
        "        ssl_certificate_key `"$keyFwd`";",
        "        ssl_protocols       TLSv1.2 TLSv1.3;",
        "        ssl_ciphers         HIGH:!aNULL:!MD5;",
        "        add_header Strict-Transport-Security `"max-age=31536000`" always;",
        "        add_header X-Frame-Options `"SAMEORIGIN`" always;",
        "        add_header X-Content-Type-Options `"nosniff`" always;",
        "        root   html;",
        "        index  index.html;",
        "        location / { try_files `$uri `$uri/ =404; }",
        "    }",
        "}"
    )
    [System.IO.File]::WriteAllLines("$nginxDir\conf\nginx.conf",
        $nginxConf, [System.Text.UTF8Encoding]::new($false))

    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxDir\nginx.exe" `
        -ArgumentList "-p `"$nginxDir`"" -WorkingDirectory $nginxDir -WindowStyle Hidden
    Start-Sleep -Seconds 2

    if (Get-Process nginx -ErrorAction SilentlyContinue) {
        # Abrir puertos en firewall de Windows
        New-NetFirewallRule -DisplayName "HTTPS-Puerto-$PuertoHTTPS" -Direction Inbound -LocalPort $PuertoHTTPS -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "HTTP-Puerto-$PuertoHTTP" -Direction Inbound -LocalPort $PuertoHTTP -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-OK "Nginx SSL habilitado en puerto $PuertoHTTPS"
        Write-OK "  Redireccion activa: $PuertoHTTP -> $PuertoHTTPS"
    } else {
        Write-Err "Nginx no pudo iniciarse"
    }
}

# =============================================================================
# FTPS PARA IIS-FTP
# =============================================================================

function SSL-IISFTP {
    if (-not (Validar-Cert)) { return }
    Write-Info "Configurando FTPS en IIS-FTP..."

    $thumb = Get-CertThumbprint
    if (-not $thumb) { Write-Err "No se encontro thumbprint"; return }

    # Buscar nombre del sitio FTP
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $sitioFTP = (Get-WebSite | Where-Object {
        Get-WebBinding -Name $_.Name -ErrorAction SilentlyContinue |
        Where-Object { $_.protocol -eq 'ftp' }
    } | Select-Object -First 1).Name

    if (-not $sitioFTP) { $sitioFTP = "FTP-Sistemas" }
    Write-Info "Sitio FTP detectado: $sitioFTP"

    # Editar applicationHost.config directamente
    $configPath = "$env:windir\System32\inetsrv\config\applicationHost.config"
    $xml = [xml](Get-Content $configPath)
    $ftpSite = $xml.configuration.'system.applicationHost'.sites.site |
               Where-Object { $_.name -eq $sitioFTP }

    if (-not $ftpSite) {
        Write-Err "Sitio FTP '$sitioFTP' no encontrado en applicationHost.config"
        return
    }

    $sslNode = $ftpSite.ftpServer.security.ssl
    if ($sslNode) {
        $sslNode.SetAttribute("serverCertHash", $thumb)
        $sslNode.SetAttribute("serverCertStoreName", "My")
        $sslNode.SetAttribute("controlChannelPolicy", "SslAllow")
        $sslNode.SetAttribute("dataChannelPolicy", "SslAllow")
        $xml.Save($configPath)
        Write-OK "Certificado FTPS configurado en applicationHost.config"
    } else {
        Write-Err "Nodo SSL no encontrado en configuracion FTP"
        return
    }

    iisreset /restart 2>$null | Out-Null
    Start-Sleep -Seconds 3
    Write-OK "FTPS habilitado en IIS-FTP ($sitioFTP)"
    Write-OK "  serverCertHash: $thumb"
}

# =============================================================================
# VERIFICACION SSL
# =============================================================================

function Verificar-SSL {
    param([int]$Puerto, [string]$Servicio)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient("localhost", $Puerto)
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($DOMAIN)
        $cert = $ssl.RemoteCertificate
        $ssl.Close(); $tcp.Close()
        Write-OK "$Servicio (localhost:${Puerto}) - SSL OK"
        Write-Host "      Subject: $($cert.Subject)"
        Write-Host "      Expira : $($cert.GetExpirationDateString())"
        return $true
    } catch {
        Write-Err "$Servicio (localhost:${Puerto}) - SSL FALLO: $_"
        return $false
    }
}

function Verificar-FTPS {
    Write-Info "Verificando FTPS en localhost:21..."
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    try {
        $req  = [System.Net.FtpWebRequest]::Create("ftp://localhost/")
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.EnableSsl   = $true
        $req.Credentials = New-Object System.Net.NetworkCredential("anonymous","")
        $req.UsePassive  = $true
        $resp = $req.GetResponse()
        $resp.Close()
        Write-OK "IIS-FTPS (localhost:21) - SSL OK"
        return $true
    } catch {
        Write-Err "IIS-FTPS - SSL FALLO: $_"
        return $false
    }
}

function Resumen-SSL {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   VERIFICACION SSL/TLS - Windows         " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $pass = 0; $fail = 0

    # IIS
    $iisHttps = Get-WebBinding -Name "Default Web Site" -Protocol https `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($iisHttps) {
        $p = [int]($iisHttps.bindingInformation -replace '.*:(\d+):.*','$1')
        if (Verificar-SSL -Puerto $p -Servicio "IIS") { $pass++ } else { $fail++ }
        Write-Host ""
    }

    # Apache
    $apacheDir = @("C:\Apache24","$env:APPDATA\Apache24") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($apacheDir) {
        $ap = Select-String "^Listen" "$apacheDir\conf\httpd.conf" |
              Where-Object { $_.Line -notmatch "^Listen 22" } |
              ForEach-Object { ($_.Line -split '\s+')[1] } | Select-Object -First 1
        if ($ap) {
            if (Verificar-SSL -Puerto ([int]$ap) -Servicio "Apache") { $pass++ } else { $fail++ }
            Write-Host ""
        }
    }

    # Nginx
    if (Test-Path "C:\nginx\conf\nginx.conf") {
        $np = Select-String "listen.*ssl" "C:\nginx\conf\nginx.conf" |
              ForEach-Object { $_.Line -replace '.*listen\s+(\d+).*','$1' } |
              Select-Object -First 1
        if ($np) {
            if (Verificar-SSL -Puerto ([int]$np) -Servicio "Nginx") { $pass++ } else { $fail++ }
            Write-Host ""
        }
    }

    # FTPS
    if (Verificar-FTPS) { $pass++ } else { $fail++ }
    Write-Host ""

    Write-Host "  +---------------------------------+"
    Write-Host "  |  OK: $pass   |  FALLO: $fail              |"
    Write-Host "  +---------------------------------+"
    Write-Host ""
}