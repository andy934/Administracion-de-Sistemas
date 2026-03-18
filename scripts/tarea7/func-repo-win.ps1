# =============================================================================
# func-repo-win.ps1 - Gestion del repositorio FTP en Windows (IIS-FTP)
# Practica 7 - Administracion de Sistemas
# Sistema: Windows Server 2022
# =============================================================================

$REPO_BASE    = "C:\inetpub\ftproot\repo"
$REPO_WIN     = "$REPO_BASE\http\Windows"
$DIR_IIS      = "$REPO_WIN\IIS"
$DIR_APACHE   = "$REPO_WIN\Apache"
$DIR_NGINX    = "$REPO_WIN\Nginx"
$FTP_HOST     = "127.0.0.1"
$FTP_USER     = "ftprepo"
$FTP_PASS     = "Repo@2026"

# =============================================================================
# VALIDACIONES
# =============================================================================

function Repo-Esta-Listo {
    if (-not (Test-Path $DIR_APACHE)) { return $false }
    if (-not (Test-Path $DIR_NGINX))  { return $false }
    $apacheBins = Get-ChildItem $DIR_APACHE -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notlike "*.sha256" }
    $nginxBins  = Get-ChildItem $DIR_NGINX  -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notlike "*.sha256" }
    return ($apacheBins.Count -gt 0 -and $nginxBins.Count -gt 0)
}

function Validar-Repo {
    if (Repo-Esta-Listo) { return $true }
    Write-Warn "El repositorio FTP no esta poblado aun"
    $r = Read-Host "  Preparar repositorio ahora? [S/n]"
    if ($r -match '^[nN]$') { return $false }
    Preparar-Repositorio-Completo
    return (Repo-Esta-Listo)
}

function Validar-IISFTP {
    $ftpSvc = Get-Service FTPSVC -ErrorAction SilentlyContinue
    $w3svc  = Get-Service W3SVC  -ErrorAction SilentlyContinue
    if ($w3svc -and $w3svc.Status -eq 'Running') { return $true }
    Write-Warn "IIS/W3SVC no esta activo (requerido para FTP)"
    $r = Read-Host "  Iniciar W3SVC ahora? [S/n]"
    if ($r -match '^[nN]$') { return $false }
    Start-Service W3SVC -ErrorAction SilentlyContinue
    return ((Get-Service W3SVC).Status -eq 'Running')
}

# =============================================================================
# CREAR USUARIO FTP DEL REPOSITORIO
# =============================================================================

function Crear-Usuario-Repo {
    Write-Info "Configurando usuario FTP del repositorio: $FTP_USER"

    $usuario = Get-LocalUser -Name $FTP_USER -ErrorAction SilentlyContinue
    if (-not $usuario) {
        $pass = ConvertTo-SecureString $FTP_PASS -AsPlainText -Force
        New-LocalUser -Name $FTP_USER -Password $pass `
            -FullName "FTP Repo Practica 7" `
            -Description "Usuario repositorio FTP P7" `
            -PasswordNeverExpires | Out-Null
        Write-OK "Usuario $FTP_USER creado (pass: $FTP_PASS)"
    } else {
        Write-Info "Usuario $FTP_USER ya existe"
    }

    # Asegurar que tenga acceso al directorio del repo
    $acl = Get-Acl $REPO_BASE -ErrorAction SilentlyContinue
    if ($acl) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $FTP_USER, "ReadAndExecute", "ContainerInherit,ObjectInherit",
            "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl $REPO_BASE $acl -ErrorAction SilentlyContinue
        Write-OK "Permisos de lectura otorgados a $FTP_USER en $REPO_BASE"
    }
}

# =============================================================================
# CREAR ESTRUCTURA DE DIRECTORIOS
# =============================================================================

function Crear-Estructura-Repo {
    Write-Info "Creando estructura de directorios del repositorio..."
    New-Item -ItemType Directory -Force -Path $DIR_IIS    | Out-Null
    New-Item -ItemType Directory -Force -Path $DIR_APACHE | Out-Null
    New-Item -ItemType Directory -Force -Path $DIR_NGINX  | Out-Null
    Write-OK "Estructura creada:"
    Write-OK "  $DIR_IIS"
    Write-OK "  $DIR_APACHE"
    Write-OK "  $DIR_NGINX"
}

# =============================================================================
# GENERAR HASH SHA256
# =============================================================================

function Generar-Hash {
    param([string]$Archivo)
    $hash = (Get-FileHash -Algorithm SHA256 -Path $Archivo).Hash.ToLower()
    $hashFile = "$Archivo.sha256"
    Set-Content -Path $hashFile -Value $hash -Encoding ASCII
    return $hash
}

# =============================================================================
# POBLAR REPOSITORIO
# =============================================================================

function Poblar-Repositorio {
    Write-Info "Poblando repositorio con binarios e instaladores..."
    Write-Host ""
    $errores = 0
    $wc = New-Object System.Net.WebClient

    # -- Apache ------------------------------------------------------------
    Write-Info "Detectando version de Apache para Windows..."
    try {
        $chocoOut = choco search apache-httpd --exact 2>$null
        $apacheVer = ($chocoOut | Where-Object { $_ -match '^apache-httpd\s+([\d\.]+)' } |
            ForEach-Object { if ($_ -match '^apache-httpd\s+([\d\.]+)') { $Matches[1] } } |
            Select-Object -First 1)
        if (-not $apacheVer) { $apacheVer = "2.4.55" }
    } catch { $apacheVer = "2.4.55" }

    # Apache en Windows se instala via Chocolatey ? guardamos un marker con la version
    $apacheMarker = "$DIR_APACHE\apache-httpd-$apacheVer-win64.choco"
    if (-not (Test-Path $apacheMarker)) {
        Set-Content -Path $apacheMarker -Value "choco:apache-httpd:$apacheVer" -Encoding ASCII
        Generar-Hash $apacheMarker | Out-Null
        Write-OK "Apache: marker $apacheVer creado + sha256"
    } else {
        Write-Info "Apache: marker ya existe en repositorio"
    }

    # -- Nginx -------------------------------------------------------------
    Write-Info "Detectando version de Nginx para Windows..."
    try {
        $html = $wc.DownloadString('https://nginx.org/en/download.html')
        $nginx_ver = [regex]::Matches($html, 'nginx-(1\.\d*[02468]\.\d+)\.zip') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object { [version]$_ } | Select-Object -Last 1
        if (-not $nginx_ver) { $nginx_ver = "1.28.2" }
    } catch { $nginx_ver = "1.28.2" }

    $nginxZip  = "$DIR_NGINX\nginx-$nginx_ver.zip"
    if (-not (Test-Path $nginxZip)) {
        Write-Info "Descargando Nginx $nginx_ver..."
        try {
            $wc.DownloadFile("https://nginx.org/download/nginx-$nginx_ver.zip", $nginxZip)
            Generar-Hash $nginxZip | Out-Null
            Write-OK "Nginx: nginx-$nginx_ver.zip + sha256 generado"
        } catch {
            Write-Warn "No se pudo descargar Nginx: $_"
            $errores++
        }
    } else {
        Write-Info "Nginx: nginx-$nginx_ver.zip ya existe en repositorio"
    }

    Write-Host ""
    if ($errores -eq 0) {
        Write-OK "Repositorio FTP listo en $REPO_BASE"
    } else {
        Write-Warn "Repositorio listo con $errores advertencias"
    }
    return $errores
}

# =============================================================================
# FLUJO COMPLETO
# =============================================================================

function Preparar-Repositorio-Completo {
    if (-not (Validar-IISFTP)) { return }
    Crear-Estructura-Repo
    Crear-Usuario-Repo
    Poblar-Repositorio
    Write-OK "Repositorio FTP Windows completamente preparado"
}

# =============================================================================
# CLIENTE FTP: LISTAR DIRECTORIO
# =============================================================================

function Listar-FTP {
    param([string]$Ruta)
    $cred = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
    try {
        $req = [System.Net.FtpWebRequest]::Create("ftp://${FTP_HOST}/${Ruta}/")
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $true
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista = @()
        while (-not $reader.EndOfStream) {
            $linea = $reader.ReadLine().Trim()
            if ($linea) { $lista += $linea }
        }
        $reader.Close(); $resp.Close()
        return $lista
    } catch {
        Write-Warn "Error listando FTP: $_"
        return @()
    }
}

# =============================================================================
# CLIENTE FTP: DESCARGAR ARCHIVO
# =============================================================================

function Descargar-FTP {
    param([string]$RutaRemota, [string]$Destino)
    Write-Info "Descargando desde FTP: ftp://${FTP_HOST}/${RutaRemota}"
    $cred = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
    try {
        $req = [System.Net.FtpWebRequest]::Create("ftp://${FTP_HOST}/${RutaRemota}")
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $true
        $resp   = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $file   = [System.IO.File]::Create($Destino)
        $stream.CopyTo($file)
        $file.Close(); $stream.Close(); $resp.Close()

        if ((Get-Item $Destino).Length -gt 0) {
            Write-OK "Descarga completada: $(Split-Path $Destino -Leaf)"
            return $true
        }
        Write-Err "Archivo descargado esta vacio"
        return $false
    } catch {
        Write-Err "Error en descarga FTP: $_"
        return $false
    }
}

# =============================================================================
# VERIFICAR INTEGRIDAD SHA256
# =============================================================================

function Verificar-Hash {
    param([string]$Archivo, [string]$RutaHashRemota)
    Write-Info "Verificando integridad de $(Split-Path $Archivo -Leaf)..."

    $tmpHash = "$env:TEMP\$(Split-Path $Archivo -Leaf).sha256.tmp"
    if (-not (Descargar-FTP $RutaHashRemota $tmpHash)) {
        Write-Err "No se pudo obtener el archivo de hash del servidor FTP"
        return $false
    }

    $hashRemoto = (Get-Content $tmpHash -Raw).Trim().ToLower()
    $hashLocal  = (Get-FileHash -Algorithm SHA256 -Path $Archivo).Hash.ToLower()
    Remove-Item $tmpHash -ErrorAction SilentlyContinue

    Write-Host "  Hash esperado : $hashRemoto"
    Write-Host "  Hash calculado: $hashLocal"

    if ($hashLocal -eq $hashRemoto) {
        Write-OK "Integridad verificada correctamente"
        return $true
    }
    Write-Err "Hash NO coincide - archivo posiblemente corrupto"
    return $false
}

# =============================================================================
# NAVEGACION INTERACTIVA DEL REPOSITORIO FTP
# =============================================================================

function Seleccionar-Desde-FTP {
    param([string]$Servicio)
    # Exporta: $script:ArchivoFTPSeleccionado, $script:RutaFTPSeleccionada
    $ruta = "http/Windows/$Servicio"

    Write-Host ""
    Write-Info "Navegando repositorio FTP: /$ruta"
    Write-Host ""

    $archivos = Listar-FTP $ruta | Where-Object {
        $_ -and $_ -notlike "*.sha256"
    }

    if (-not $archivos -or $archivos.Count -eq 0) {
        Write-Err "No hay archivos en el repositorio para $Servicio"
        Write-Err "Ejecuta primero: Opcion 1 - Preparar repositorio FTP"
        return $false
    }

    $lista = @($archivos)
    Write-Host "  Archivos disponibles en FTP/$Servicio:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $lista.Count; $i++) {
        Write-Host "    $($i+1). $($lista[$i])"
    }
    Write-Host ""

    $sel = 0
    while ($sel -lt 1 -or $sel -gt $lista.Count) {
        $inp = Read-Host "  Seleccione archivo (1-$($lista.Count))"
        if ($inp -match '^\d+$') { $sel = [int]$inp }
    }

    $script:ArchivoFTPSeleccionado = $lista[$sel - 1]
    $script:RutaFTPSeleccionada    = "$ruta/$($script:ArchivoFTPSeleccionado)"
    Write-OK "Seleccionado: $($script:ArchivoFTPSeleccionado)"
    return $true
}

# =============================================================================
# MOSTRAR ESTADO DEL REPOSITORIO
# =============================================================================

function Mostrar-Estado-Repo {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DEL REPOSITORIO FTP (Windows)  " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($svc in @("IIS", "Apache", "Nginx")) {
        $dir = "$REPO_WIN\$svc"
        $bins   = 0
        $hashes = 0
        if (Test-Path $dir) {
            $bins   = (Get-ChildItem $dir | Where-Object { $_.Name -notlike "*.sha256" }).Count
            $hashes = (Get-ChildItem $dir | Where-Object { $_.Name -like "*.sha256" }).Count
        }
        Write-Host "  $svc`: Binarios=$bins  Hashes=$hashes"
        if (Test-Path $dir) {
            Get-ChildItem $dir | Where-Object { $_.Name -notlike "*.sha256" } |
                ForEach-Object { Write-Host "       - $($_.Name)" }
        }
    }

    Write-Host ""
    $ftpSt = (Get-Service W3SVC -ErrorAction SilentlyContinue).Status
    $col = if ($ftpSt -eq 'Running') { "Green" } else { "Red" }
    Write-Host "  IIS/W3SVC: $ftpSt" -ForegroundColor $col
    Write-Host ""
}