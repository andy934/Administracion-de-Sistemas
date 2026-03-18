# =============================================================================
# func-ssl-win.ps1 - Generacion de certificados SSL/TLS para Windows
# Practica 7 - Administracion de Sistemas
# Sistema: Windows Server 2022
# =============================================================================

$SSL_DIR    = "C:\ssl\tarea7"
$DOMAIN     = "reprobados.com"
$CERT_PATH  = "$SSL_DIR\reprobados.crt"
$KEY_PATH   = "$SSL_DIR\reprobados.key"
$PFX_PATH   = "$SSL_DIR\reprobados.pfx"
$PFX_PASS   = "tarea7ssl"
$CERT_STORE = "Cert:\LocalMachine\My"
$DAYS       = 365

# =============================================================================
# VALIDACION: CERTIFICADO EXISTE
# =============================================================================

function Cert-Existe {
    return (Test-Path $PFX_PATH) -and
           (Get-ChildItem $CERT_STORE | Where-Object { $_.Subject -like "*$DOMAIN*" })
}

function Validar-Cert {
    if (Cert-Existe) { return $true }
    Write-Warn "No existe certificado SSL para $DOMAIN"
    $r = Read-Host "  Generar certificado ahora? [S/n]"
    if ($r -match '^[nN]$') { return $false }
    Generar-Certificado
    return (Cert-Existe)
}

# =============================================================================
# GENERAR CERTIFICADO AUTOFIRMADO
# =============================================================================

function Generar-Certificado {
    Write-Info "Generando certificado SSL autofirmado para $DOMAIN..."

    New-Item -ItemType Directory -Force -Path $SSL_DIR | Out-Null

    # Verificar si ya existe
    $existing = Get-ChildItem $CERT_STORE | Where-Object { $_.Subject -like "*$DOMAIN*" }
    if ($existing) {
        Write-Warn "Certificado ya existe en el store"
        $r = Read-Host "  Regenerar? [s/N]"
        if ($r -notmatch '^[sS]$') {
            Write-OK "Usando certificado existente"
            # Exportar PFX si no existe
            if (-not (Test-Path $PFX_PATH)) {
                $pass = ConvertTo-SecureString $PFX_PASS -AsPlainText -Force
                Export-PfxCertificate -Cert $existing[0] -FilePath $PFX_PATH -Password $pass | Out-Null
                Write-OK "PFX exportado: $PFX_PATH"
            }
            return
        }
        # Eliminar certificado anterior
        $existing | Remove-Item -ErrorAction SilentlyContinue
    }

    # Generar nuevo certificado
    $cert = New-SelfSignedCertificate `
        -DnsName $DOMAIN, "www.$DOMAIN", "localhost" `
        -CertStoreLocation $CERT_STORE `
        -NotAfter (Get-Date).AddDays($DAYS) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") `
        -FriendlyName "Tarea7-$DOMAIN"

    if (-not $cert) {
        Write-Err "Fallo la generacion del certificado"
        return
    }

    # Exportar a PFX
    $pass = ConvertTo-SecureString $PFX_PASS -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $PFX_PATH -Password $pass | Out-Null

    # Exportar CRT (para referencia)
    Export-Certificate -Cert $cert -FilePath $CERT_PATH -Type CERT | Out-Null

    # Agregar a Trusted Root para evitar warnings
    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        "Root", "LocalMachine")
    $rootStore.Open("ReadWrite")
    $rootStore.Add($cert)
    $rootStore.Close()

    Write-OK "Certificado generado exitosamente:"
    Write-OK "  Thumbprint : $($cert.Thumbprint)"
    Write-OK "  Subject    : $($cert.Subject)"
    Write-OK "  Expira     : $($cert.NotAfter)"
    Write-OK "  PFX        : $PFX_PATH"
    Write-OK "  Store      : $CERT_STORE"
}

# =============================================================================
# OBTENER THUMBPRINT DEL CERTIFICADO
# =============================================================================

function Get-CertThumbprint {
    $cert = Get-ChildItem $CERT_STORE |
            Where-Object { $_.Subject -like "*$DOMAIN*" } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
    return $cert.Thumbprint
}

# =============================================================================
# SSL PARA IIS (puerto 443)
# =============================================================================

function SSL-IIS {
    param([int]$PuertoHTTP = 222, [int]$PuertoHTTPS = 443)

    if (-not (Validar-Cert)) { return }

    Write-Info "Configurando SSL en IIS (HTTP:$PuertoHTTP -> HTTPS:$PuertoHTTPS)..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $sitio = "Default Web Site"
    $thumb = Get-CertThumbprint

    if (-not $thumb) {
        Write-Err "No se encontro thumbprint del certificado"
        return
    }

    # Agregar binding HTTPS si no existe
    $bindingExiste = Get-WebBinding -Name $sitio -Protocol https -ErrorAction SilentlyContinue |
                     Where-Object { $_.bindingInformation -like "*:${PuertoHTTPS}:*" }

    if (-not $bindingExiste) {
        New-WebBinding -Name $sitio -Protocol https -Port $PuertoHTTPS -IPAddress "*"
        Write-OK "Binding HTTPS agregado en puerto $PuertoHTTPS"
    } else {
        Write-Info "Binding HTTPS ya existe en puerto $PuertoHTTPS"
    }

    # Asignar certificado al binding HTTPS
    $cert = Get-ChildItem $CERT_STORE | Where-Object { $_.Thumbprint -eq $thumb }
    if ($cert) {
        $binding = Get-WebBinding -Name $sitio -Protocol https -Port $PuertoHTTPS
        $binding.AddSslCertificate($thumb, "My")
        Write-OK "Certificado asignado al binding HTTPS"
    }

    # Redireccion HTTP -> HTTPS via web.config
    $wwwroot = "C:\inetpub\wwwroot"
    $webConfig = "$wwwroot\web.config"
    $webConfigContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HTTP to HTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="^OFF$" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
    <security>
      <requestFiltering removeServerHeader="true" />
    </security>
  </system.webServer>
</configuration>
'@
    # Instalar URL Rewrite si no esta disponible
    $rewriteModulo = Get-WebConfiguration "system.webServer/rewrite" -ErrorAction SilentlyContinue
    if (-not $rewriteModulo) {
        Write-Warn "Modulo URL Rewrite no instalado - redireccion HTTP->HTTPS no disponible"
        Write-Warn "Instalar desde: https://www.iis.net/downloads/microsoft/url-rewrite"
    } else {
        Set-Content -Path $webConfig -Value $webConfigContent -Encoding UTF8
        Write-OK "Redireccion HTTP->HTTPS configurada via web.config"
    }

    iisreset /restart | Out-Null
    Start-Sleep -Seconds 3

    if ((Get-Service W3SVC).Status -eq 'Running') {
        Write-OK "IIS SSL habilitado en puerto $PuertoHTTPS"
    } else {
        Write-Err "IIS no pudo reiniciarse"
    }
}

# =============================================================================
# SSL PARA APACHE (puerto 443 o personalizado)
# =============================================================================

function SSL-Apache {
    param([int]$PuertoHTTP = 223, [int]$PuertoHTTPS = 453)

    if (-not (Validar-Cert)) { return }

    $apacheDir = @("C:\Apache24",
                   "C:\Program Files\Apache Software Foundation\Apache2.4",
                   "$env:APPDATA\Apache24") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $apacheDir) {
        Write-Err "Apache no encontrado"
        Write-Err "Instala Apache primero (Opcion 3 del menu)"
        return
    }

    Write-Info "Configurando SSL en Apache ($apacheDir)..."
    Write-Info "  HTTP:$PuertoHTTP -> HTTPS:$PuertoHTTPS"

    $httpdConf  = "$apacheDir\conf\httpd.conf"
    $extraDir   = "$apacheDir\conf\extra"

    # Habilitar modulos SSL
    $conf = Get-Content $httpdConf
    $conf = $conf -replace '#LoadModule ssl_module',       'LoadModule ssl_module'
    $conf = $conf -replace '#LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $conf = $conf -replace '#LoadModule rewrite_module',   'LoadModule rewrite_module'
    $conf = $conf -replace '#LoadModule headers_module',   'LoadModule headers_module'

    # Agregar puerto HTTPS si no existe
    if (-not ($conf -match "^Listen $PuertoHTTPS")) {
        $conf += "Listen $PuertoHTTPS"
    }

    # Incluir archivos SSL
    if (-not ($conf -match "httpd-ssl-tarea7.conf")) {
        $conf += "Include conf/extra/httpd-ssl-tarea7.conf"
    }
    if (-not ($conf -match "httpd-redirect-tarea7.conf")) {
        $conf += "Include conf/extra/httpd-redirect-tarea7.conf"
    }

    $conf | Set-Content $httpdConf -Encoding UTF8

    # Exportar certificado a formato PEM para Apache
    $pemCert = "$SSL_DIR\reprobados-apache.crt"
    $pemKey  = "$SSL_DIR\reprobados-apache.key"

    $pass = ConvertTo-SecureString $PFX_PASS -AsPlainText -Force
    $certObj = Get-PfxData -FilePath $PFX_PATH -Password $pass

    # Exportar CRT en formato PEM
    $certBytes = $certObj.EndEntityCertificates[0].Export(
        [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $pemBody = [Convert]::ToBase64String($certBytes, 'InsertLineBreaks')
    "-----BEGIN CERTIFICATE-----`n$pemBody`n-----END CERTIFICATE-----" |
        Set-Content $pemCert -Encoding ASCII

    # Para la llave privada necesitamos openssl si esta disponible
    $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($opensslPath) {
        & openssl pkcs12 -in $PFX_PATH -nocerts -nodes `
            -passin "pass:$PFX_PASS" -out $pemKey 2>$null
        Write-OK "Llave privada exportada a PEM"
    } else {
        # Usar el PFX directamente no es posible en Apache
        # Alternativa: copiar certs del script de Linux si disponibles
        Write-Warn "openssl no encontrado - usando PFX directamente"
        $pemCert = $PFX_PATH
        $pemKey  = $PFX_PATH
    }

    # VirtualHost HTTPS
    $sslConf = @(
        "# VirtualHost HTTPS - generado por Practica 7",
        "<VirtualHost *:$PuertoHTTPS>",
        "    ServerName $DOMAIN",
        "    ServerAlias www.$DOMAIN",
        "    SSLEngine on",
        "    SSLCertificateFile    `"$pemCert`"",
        "    SSLCertificateKeyFile `"$pemKey`"",
        "    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1",
        "    SSLCipherSuite        HIGH:!aNULL:!MD5:!3DES",
        "    DocumentRoot `"$apacheDir/htdocs`"",
        "    Header always set Strict-Transport-Security `"max-age=31536000`"",
        "    Header always set X-Frame-Options `"SAMEORIGIN`"",
        "    Header always set X-Content-Type-Options `"nosniff`"",
        "</VirtualHost>"
    )
    [System.IO.File]::WriteAllLines("$extraDir\httpd-ssl-tarea7.conf",
        $sslConf, [System.Text.UTF8Encoding]::new($false))

    # Redireccion HTTP -> HTTPS
    $redirConf = @(
        "# Redireccion HTTP -> HTTPS - generado por Practica 7",
        "<VirtualHost *:$PuertoHTTP>",
        "    ServerName $DOMAIN",
        "    RewriteEngine On",
        "    RewriteRule ^(.*)$ https://%{HTTP_HOST}`$1 [R=301,L]",
        "</VirtualHost>"
    )
    [System.IO.File]::WriteAllLines("$extraDir\httpd-redirect-tarea7.conf",
        $redirConf, [System.Text.UTF8Encoding]::new($false))

    # Verificar y reiniciar
    $test = & "$apacheDir\bin\httpd.exe" -t 2>&1
    if ($test -match "Syntax OK") {
        Restart-Service Apache -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-OK "Apache SSL habilitado en puerto $PuertoHTTPS"
        Write-OK "  Redireccion activa: $PuertoHTTP -> $PuertoHTTPS"
    } else {
        Write-Err "Error en configuracion de Apache:"
        $test | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" }
    }
}

# =============================================================================
# SSL PARA NGINX (puerto 443 o personalizado)
# =============================================================================

function SSL-Nginx {
    param([int]$PuertoHTTP = 204, [int]$PuertoHTTPS = 454)

    if (-not (Validar-Cert)) { return }

    $nginxDir = "C:\nginx"
    if (-not (Test-Path "$nginxDir\nginx.exe")) {
        Write-Err "Nginx no encontrado en $nginxDir"
        Write-Err "Instala Nginx primero (Opcion 4 del menu)"
        return
    }

    Write-Info "Configurando SSL en Nginx (HTTP:$PuertoHTTP -> HTTPS:$PuertoHTTPS)..."

    # Exportar certificado a PEM para Nginx
    $pemCert = "$SSL_DIR\reprobados-nginx.crt"
    $pemKey  = "$SSL_DIR\reprobados-nginx.key"

    $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($opensslPath) {
        & openssl pkcs12 -in $PFX_PATH -clcerts -nokeys `
            -passin "pass:$PFX_PASS" -out $pemCert 2>$null
        & openssl pkcs12 -in $PFX_PATH -nocerts -nodes `
            -passin "pass:$PFX_PASS" -out $pemKey 2>$null
        Write-OK "Certificados PEM exportados para Nginx"
    } else {
        # Sin openssl: exportar CRT desde store
        $certBytes = (Get-ChildItem $CERT_STORE |
            Where-Object { $_.Subject -like "*$DOMAIN*" } |
            Select-Object -First 1).Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $pemBody = [Convert]::ToBase64String($certBytes, 'InsertLineBreaks')
        "-----BEGIN CERTIFICATE-----`n$pemBody`n-----END CERTIFICATE-----" |
            Set-Content $pemCert -Encoding ASCII
        Write-Warn "openssl no disponible - llave privada no exportada, SSL puede fallar"
        $pemKey = $pemCert
    }

    $nginxConf = @(
        "worker_processes  auto;",
        "error_log  logs/error.log warn;",
        "pid        logs/nginx.pid;",
        "events { worker_connections 1024; }",
        "http {",
        "    include       mime.types;",
        "    default_type  application/octet-stream;",
        "    server_tokens off;",
        "    sendfile on;",
        "    keepalive_timeout 65;",
        "    server {",
        "        listen $PuertoHTTP;",
        "        server_name $DOMAIN www.$DOMAIN;",
        "        return 301 https://`$host`$request_uri;",
        "    }",
        "    server {",
        "        listen $PuertoHTTPS ssl;",
        "        server_name $DOMAIN www.$DOMAIN;",
        "        ssl_certificate     `"$pemCert`";",
        "        ssl_certificate_key `"$pemKey`";",
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

    # Matar proceso nginx previo y reiniciar
    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxDir\nginx.exe" `
        -ArgumentList "-p `"$nginxDir`"" `
        -WorkingDirectory $nginxDir -WindowStyle Hidden
    Start-Sleep -Seconds 2

    if (Get-Process nginx -ErrorAction SilentlyContinue) {
        Write-OK "Nginx SSL habilitado en puerto $PuertoHTTPS"
        Write-OK "  Redireccion activa: $PuertoHTTP -> $PuertoHTTPS"
    } else {
        Write-Err "Nginx no pudo iniciarse con SSL"
    }
}

# =============================================================================
# FTPS PARA IIS-FTP
# =============================================================================

function SSL-IISFTP {
    if (-not (Validar-Cert)) { return }

    Write-Info "Configurando FTPS (SSL/TLS) en IIS-FTP..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $thumb = Get-CertThumbprint
    if (-not $thumb) {
        Write-Err "No se encontro thumbprint del certificado"
        return
    }

    $sitioFTP = "FTP-Sistemas"
    $ftpSite  = Get-WebSite -Name $sitioFTP -ErrorAction SilentlyContinue
    if (-not $ftpSite) {
        # Buscar cualquier sitio FTP
        $ftpSite = Get-WebSite | Where-Object {
            (Get-WebBinding -Name $_.Name | Where-Object { $_.protocol -eq 'ftp' })
        } | Select-Object -First 1
        if ($ftpSite) { $sitioFTP = $ftpSite.Name }
        else {
            Write-Err "No se encontro sitio FTP en IIS"
            return
        }
    }

    # Configurar SSL en el sitio FTP
    Set-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST/$sitioFTP" `
        -Filter "system.ftpServer/security/ssl" `
        -Name "serverCertHash" -Value $thumb -ErrorAction SilentlyContinue

    Set-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST/$sitioFTP" `
        -Filter "system.ftpServer/security/ssl" `
        -Name "controlChannelPolicy" -Value "SslAllow" -ErrorAction SilentlyContinue

    Set-WebConfigurationProperty `
        -PSPath "MACHINE/WEBROOT/APPHOST/$sitioFTP" `
        -Filter "system.ftpServer/security/ssl" `
        -Name "dataChannelPolicy" -Value "SslAllow" -ErrorAction SilentlyContinue

    iisreset /restart | Out-Null
    Start-Sleep -Seconds 3

    Write-OK "FTPS habilitado en IIS-FTP ($sitioFTP)"
    Write-OK "  Canal de control: SSL permitido"
    Write-OK "  Canal de datos  : SSL permitido"
}

# =============================================================================
# VERIFICACION SSL INDIVIDUAL
# =============================================================================

function Verificar-SSL {
    param([string]$Host = "localhost", [int]$Puerto, [string]$Servicio)
    try {
        $tcp  = New-Object System.Net.Sockets.TcpClient($Host, $Puerto)
        $ssl  = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false,
            { $true })  # aceptar cualquier certificado
        $ssl.AuthenticateAsClient($DOMAIN)
        $cert = $ssl.RemoteCertificate
        $ssl.Close(); $tcp.Close()

        Write-OK "$Servicio (${Host}:${Puerto}) ? SSL OK"
        Write-Host "      Subject : $($cert.Subject)"
        Write-Host "      Expira  : $($cert.GetExpirationDateString())"
        return $true
    } catch {
        Write-Err "$Servicio (${Host}:${Puerto}) ? SSL FALLO: $_"
        return $false
    }
}

function Verificar-FTPS {
    param([string]$Host = "localhost")
    Write-Info "Verificando FTPS en ${Host}:21..."
    try {
        $req  = [System.Net.FtpWebRequest]::Create("ftp://${Host}/")
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.EnableSsl   = $true
        $req.Credentials = New-Object System.Net.NetworkCredential("anonymous", "")
        $req.UsePassive  = $true
        $cb = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        $resp = $req.GetResponse()
        $resp.Close()
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $cb
        Write-OK "IIS-FTPS (${Host}:21) ? SSL OK"
        return $true
    } catch {
        Write-Err "IIS-FTPS (${Host}:21) ? SSL FALLO o no configurado"
        return $false
    }
}

# =============================================================================
# RESUMEN AUTOMATIZADO SSL
# =============================================================================

function Resumen-SSL {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   VERIFICACION AUTOMATIZADA SSL/TLS      " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $pass = 0; $fail = 0

    # IIS HTTPS
    $iisHttps = (Get-WebBinding -Name "Default Web Site" -Protocol https `
        -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($iisHttps) {
        $puerto = $iisHttps.bindingInformation -replace '.*:(\d+):.*','$1'
        if (Verificar-SSL -Puerto $puerto -Servicio "IIS") { $pass++ } else { $fail++ }
    }
    Write-Host ""

    # Apache HTTPS
    $apacheDir = @("C:\Apache24","$env:APPDATA\Apache24") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($apacheDir) {
        $apacheHttps = Select-String "^Listen" "$apacheDir\conf\httpd.conf" |
            Where-Object { $_.Line -notmatch "^Listen $($script:PuertoApacheHTTP)" } |
            ForEach-Object { ($_.Line -split '\s+')[1] } | Select-Object -First 1
        if ($apacheHttps) {
            if (Verificar-SSL -Puerto $apacheHttps -Servicio "Apache") { $pass++ } else { $fail++ }
        }
    }
    Write-Host ""

    # Nginx HTTPS
    if (Test-Path "C:\nginx\conf\nginx.conf") {
        $nginxHttps = Select-String "listen.*ssl" "C:\nginx\conf\nginx.conf" |
            ForEach-Object { $_.Line -replace '.*listen\s+(\d+).*','$1' } |
            Select-Object -First 1
        if ($nginxHttps) {
            if (Verificar-SSL -Puerto $nginxHttps -Servicio "Nginx") { $pass++ } else { $fail++ }
        }
    }
    Write-Host ""

    # IIS-FTPS
    if (Verificar-FTPS) { $pass++ } else { $fail++ }
    Write-Host ""

    Write-Host "  +---------------------------------+"
    Write-Host "  |  OK: $pass   |  FALLO: $fail              |"
    Write-Host "  +---------------------------------+"
    Write-Host ""
}
