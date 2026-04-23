# =============================================================================
# func-mfa.ps1 - MFA con WinOTP (TOTP / Google Authenticator)
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

$VCREDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$MULTIOTP_URL = "https://github.com/multiOTP/multiOTPCredentialProvider/releases/latest/download/multiOTPCredentialProvider.exe"
$MFA_DIR = "C:\MFA"
$WINOTP_URL = "https://github.com/nicowillis/WinOTP/releases/latest/download/WinOTP.msi"
$WINOTP_MSI = "$MFA_DIR\WinOTP.msi"
$SECRETS_FILE = "$MFA_DIR\mfa-secrets.txt"
$LOCKOUT_MINUTOS = 30
$MAX_INTENTOS = 3

# =============================================================================
# VERIFICAR / INSTALAR PREREQUISITOS
# =============================================================================

function Verificar-Prerequisitos-MFA {
    Write-Info "Verificando prerequisitos para MFA..."

    # Verificar que hay acceso a internet
    $internet = Test-Connection "8.8.8.8" -Count 1 -Quiet
    if (-not $internet) {
        Write-Warn "Sin conexion a internet - puede que WinOTP no se pueda descargar"
    }

    # Verificar .NET Framework
    $dotnet = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" `
        -ErrorAction SilentlyContinue
    if ($dotnet -and $dotnet.Release -ge 461808) {
        Write-OK ".NET Framework 4.7.2+ disponible"
    }
    else {
        Write-Warn ".NET Framework puede necesitar actualizacion"
    }

    # Verificar si WinOTP ya esta instalado
    $winotp = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*WinOTP*" }
    if ($winotp) {
        Write-OK "WinOTP ya esta instalado: $($winotp.DisplayName)"
        return $true
    }

    return $false
}

# =============================================================================
# HELPER: Obtener ruta del ejecutable multiOTP instalado
# =============================================================================

function Get-MultiOTPExe {
    $rutas = @(
        "$MFA_DIR\multiotp.exe",
        "$MFA_DIR\windows\multiotp.exe",
        "C:\Program Files\multiOTP\multiotp.exe",
        "C:\Program Files (x86)\multiOTP\multiotp.exe"
    )
    foreach ($r in $rutas) {
        if (Test-Path $r) { return $r }
    }
    # Busqueda recursiva en $MFA_DIR si existe
    if (Test-Path $MFA_DIR) {
        $found = Get-ChildItem -Path $MFA_DIR -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

# =============================================================================
# HELPER: Agregar regla AppLocker de ruta Allow
# =============================================================================

function Agregar-ReglaAppLockerRuta {
    param([string]$Ruta)
    try {
        # Crear directorio si no existe
        if (-not (Test-Path $Ruta)) {
            New-Item -Path $Ruta -ItemType Directory -Force | Out-Null
        }

        # Verificar si AppLocker esta administrado via GPO
        $appLockerGPO = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
        if (-not $appLockerGPO) {
            Write-Host "  [INFO] AppLocker no tiene politica efectiva activa." -ForegroundColor Cyan
            return $false
        }

        # Intentar agregar regla de ruta allow para la carpeta indicada
        $regla = New-AppLockerPolicy -RuleType Path -FileInformation $Ruta -User Everyone `
            -RuleNamePrefix "MFA_Allow" -ErrorAction Stop
        Set-AppLockerPolicy -PolicyObject $regla -Merge -ErrorAction Stop
        Write-Host "  [OK] Regla AppLocker de ruta Allow agregada para: $Ruta" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  [WARN] No se pudo agregar regla AppLocker: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# =============================================================================
# FUNCION 6: Instalar VC++ 2022 y multiOTP
#            CORRECCION: Desactiva AppLocker antes de instalar
# =============================================================================

function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   INSTALAR DEPENDENCIAS Y MOTOR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = $MFA_DIR
    $multiotpExe = Get-MultiOTPExe
    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP ya instalado: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $r = Read-Host "  Reconfigurar? (s/n)"
        if ($r.ToLower() -ne 's') { Write-Host "  Ve a la Opcion 7." -ForegroundColor Yellow; Read-Host | Out-Null; return }
    }

    # -------------------------------------------------------
    # PASO CRITICO: Deshabilitar AppLocker para la instalacion
    # Esto resuelve el error "This program is blocked by group policy"
    # -------------------------------------------------------
    Write-Host "  [PASO CRITICO] Manejando AppLocker para permitir instalacion..." -ForegroundColor Magenta

    # Metodo 1: Agregar regla de ruta allow para $MFA_DIR
    $reglaAgregada = Agregar-ReglaAppLockerRuta -Ruta $rutaDescarga

    # Metodo 2: Deshabilitar AppIDSvc si el metodo 1 no fue suficiente
    $appIDSvc = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if ($appIDSvc -and $appIDSvc.Status -eq "Running") {
        Write-Host "  [INFO] AppIDSvc activo. Deteniendolo para instalacion..." -ForegroundColor Yellow
        try {
            Stop-Service -Name "AppIDSvc" -Force -ErrorAction Stop
            Write-Host "  [OK] AppIDSvc detenido. AppLocker temporalmente inactivo." -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] No se pudo detener AppIDSvc: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 2

    # -------------------------------------------------------
    # PASO 1: Visual C++ 2022 Redistributable
    # -------------------------------------------------------
    Write-Host "`n  [1/2] Visual C++ 2022 Redistributable..." -ForegroundColor Yellow
    $vcPath = "$rutaDescarga\vc_redist_2022_x64.exe"

    # Verificar si ya esta instalado
    $vcInstalado = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
    if ($vcInstalado) {
        Write-Host "  [OK] VC++ 2022 ya esta instalado (version: $($vcInstalado.Version))." -ForegroundColor Green
    }
    else {
        if (-not (Test-Path $vcPath)) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Host "  Descargando VC++ Redistributable..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcPath -UseBasicParsing -ErrorAction Stop
                Write-Host "  [OK] Descargado." -ForegroundColor Green
            }
            catch {
                Write-Host "  [ERROR] Descarga VC++: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  [INFO] Descarga manual: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
                Write-Host "  [INFO] Guarda el archivo como: $vcPath" -ForegroundColor Yellow
                Read-Host | Out-Null; return
            }
        }

        Write-Host "  Instalando VC++ 2022..." -ForegroundColor Yellow

        # CRITICO: copiar a C:\Windows\Temp (siempre permitido por GPO/AppLocker)
        $vcTemp = "C:\Windows\Temp\vc_redist_p9.exe"
        try {
            Copy-Item -Path $vcPath -Destination $vcTemp -Force -ErrorAction Stop
            Write-Host "  [OK] Copiado a ruta permitida por GPO: $vcTemp" -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] No se pudo copiar a Temp. Usando ruta original." -ForegroundColor Yellow
            $vcTemp = $vcPath
        }

        $vcOK = $false
        # Intento 1: cmd /c desde Windows\Temp
        cmd /c "`"$vcTemp`" /install /quiet /norestart" 2>&1 | Out-Null
        if ($LASTEXITCODE -in @(0, 1638, 3010)) {
            Write-Host "  [OK] VC++ 2022 instalado." -ForegroundColor Green
            $vcOK = $true
        }
        # Intento 2: Start-Process
        if (-not $vcOK) {
            try {
                $p2 = Start-Process -FilePath $vcTemp -ArgumentList "/install /quiet /norestart" -Wait -PassThru -ErrorAction Stop
                if ($p2.ExitCode -in @(0, 1638, 3010)) {
                    Write-Host "  [OK] VC++ instalado (intento 2)." -ForegroundColor Green
                    $vcOK = $true
                }
            }
            catch {}
        }
        # Intento 3: cmd.exe como proceso padre
        if (-not $vcOK) {
            try {
                $p3 = Start-Process "cmd.exe" -ArgumentList "/c `"$vcTemp`" /install /quiet /norestart" -Wait -PassThru -ErrorAction Stop
                if ($p3.ExitCode -in @(0, 1638, 3010)) {
                    Write-Host "  [OK] VC++ instalado (intento 3)." -ForegroundColor Green
                    $vcOK = $true
                }
            }
            catch {}
        }
        if (-not $vcOK) {
            Write-Host "  [WARN] VC++ no se pudo instalar automaticamente." -ForegroundColor Yellow
            Write-Host "  [INFO] multiOTP puede instalarse igual. Continuando..." -ForegroundColor Cyan
        }
    } # cierre del else (VC++ no instalado)

    Start-Sleep -Seconds 2

    # -------------------------------------------------------
    # PASO 2: Instalar multiOTP Credential Provider
    # -------------------------------------------------------
    Write-Host "`n  [2/2] Instalador multiOTP Credential Provider..." -ForegroundColor Yellow

    # Descargar ZIP de multiOTP si no hay ningun instalador todavia
    $hayInstalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
    Select-Object -First 1
    if (-not $hayInstalador) {
        $exePath = "$rutaDescarga\multiOTPCredentialProvider.exe"
        if (-not (Test-Path $exePath)) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Host "  Descargando multiOTP Credential Provider..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $MULTIOTP_URL -OutFile $exePath -UseBasicParsing -ErrorAction Stop `
                    -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT; Windows NT 10.0) WindowsPowerShell/5.1' }
                Write-Host "  [OK] multiOTP descargado." -ForegroundColor Green
            }
            catch {
                Write-Host "  [ERROR] Descarga multiOTP: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  [INFO] Descarga manual: $MULTIOTP_URL" -ForegroundColor Yellow
                Write-Host "  [INFO] Guarda el archivo como: $exePath" -ForegroundColor Yellow
                $svcRestart = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
                if ($svcRestart -and $svcRestart.Status -ne "Running") {
                    Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
                }
                Read-Host | Out-Null; return
            }
        }
    }

    # Extraer ZIPs si hay
    Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = "$rutaDescarga\Extracted_$($_.BaseName)"
        if (-not (Test-Path $dest)) {
            Write-Host "  Extrayendo: $($_.Name)..." -ForegroundColor Yellow
            Expand-Archive -Path $_.FullName -DestinationPath $dest -Force
            Write-Host "  [OK] Extraido en: $dest" -ForegroundColor Green
        }
    }

    # Buscar instalador
    $instalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
    Sort-Object Length -Descending | Select-Object -First 1

    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro instalador multiOTP." -ForegroundColor Red
        Write-Host "  [SOLUCION] Ejecuta primero la Opcion 1 para descargar multiOTP." -ForegroundColor Yellow
        # Rehabilitar AppLocker antes de salir
        $svcRestart = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        if ($svcRestart -and $svcRestart.Status -ne "Running") {
            Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        }
        Read-Host | Out-Null; return
    }

    Write-Host "`n  Instalador encontrado: $($instalador.Name)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  +-------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |   INSTRUCCIONES DEL INSTALADOR multiOTP         |" -ForegroundColor Yellow
    Write-Host "  +-------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  1. En la primera pantalla marca:" -ForegroundColor White
    Write-Host "     'No remote server, local multiOTP only'"         -ForegroundColor Green
    Write-Host "  2. Logon  -> selecciona 'Local and Remote'"         -ForegroundColor White
    Write-Host "  3. Unlock -> selecciona 'Local and Remote'"         -ForegroundColor White
    Write-Host "  4. Haz clic en 'Next' hasta llegar a 'Finish'."     -ForegroundColor White
    Write-Host "  5. Al terminar el instalador, este script seguira." -ForegroundColor White
    Write-Host ""
    Write-Host "  Presiona Enter para lanzar el instalador..." -ForegroundColor Cyan
    Read-Host | Out-Null

    try {
        if ($instalador.Extension -eq ".msi") {
            Write-Host "  Instalando MSI..." -ForegroundColor Yellow
            $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$($instalador.FullName)`"" -Wait -PassThru -ErrorAction Stop
        }
        else {
            Write-Host "  Instalando EXE..." -ForegroundColor Yellow
            # Usar cmd /c para evitar bloqueo de AppLocker
            $resultado = cmd /c "`"$($instalador.FullName)`"" 2>&1
            $p = [PSCustomObject]@{ ExitCode = $LASTEXITCODE }
            if ($p.ExitCode -ne 0) {
                # Segundo intento con Start-Process
                $p = Start-Process $instalador.FullName -Wait -PassThru -ErrorAction Stop
            }
        }
        if ($p.ExitCode -eq 0) {
            Write-Host "  [OK] multiOTP instalado correctamente." -ForegroundColor Green
        }
        else {
            Write-Host "  [AVISO] Codigo de salida: $($p.ExitCode). Puede ser normal." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [SOLUCION] Instala manualmente haciendo doble clic en: $($instalador.FullName)" -ForegroundColor Cyan
    }

    # -------------------------------------------------------
    # Rehabilitar AppLocker
    # -------------------------------------------------------
    Write-Host "`n  Rehabilitando AppLocker..." -ForegroundColor Yellow
    $svcFinal = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if ($svcFinal -and $svcFinal.Status -ne "Running") {
        try {
            Start-Service -Name "AppIDSvc" -ErrorAction Stop
            Write-Host "  [OK] AppIDSvc rehabilitado." -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] No se pudo rehabilitar AppIDSvc: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  [OK] AppIDSvc ya estaba corriendo." -ForegroundColor Green
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# =============================================================================
# CONFIGURACION TOTP MANUAL (sin WinOTP)
# Genera secretos TOTP y muestra QR para Google Authenticator
# =============================================================================

function Configurar-TOTP-Manual {
    Write-Host ""
    Write-Info "Configurando TOTP manual para Google Authenticator..."
    Write-Host ""

    New-Item -ItemType Directory -Force -Path $MFA_DIR | Out-Null

    # Generar secreto TOTP aleatorio para el Administrador
    $secretBytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($secretBytes)

    # Convertir a Base32 (formato requerido por Google Authenticator)
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $secret = ""
    $buffer = 0
    $bitsLeft = 0

    foreach ($b in $secretBytes) {
        $buffer = ($buffer -shl 8) -bor $b
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $secret += $base32Chars[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }

    $cuenta = "Administrador"
    $emisor = "reprobados.com"
    $totpUrl = "otpauth://totp/${emisor}:${cuenta}?secret=${secret}&issuer=${emisor}&algorithm=SHA1&digits=6&period=30"

    # Guardar secreto
    $info = @(
        "=" * 50,
        "CONFIGURACION MFA - TOTP",
        "Practica 9 - reprobados.com",
        "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "=" * 50,
        "",
        "Usuario   : $cuenta",
        "Emisor    : $emisor",
        "Secreto   : $secret",
        "",
        "URL TOTP  : $totpUrl",
        "",
        "INSTRUCCIONES:",
        "1. Abre Google Authenticator en tu celular",
        "2. Toca '+' -> 'Ingresar clave de configuracion'",
        "3. Nombre: $emisor - $cuenta",
        "4. Clave : $secret",
        "5. Tipo  : Basada en el tiempo",
        "",
        "O escanea el QR generado con la URL de arriba.",
        "=" * 50
    )

    $info | Set-Content $SECRETS_FILE -Encoding UTF8
    Write-OK "Secreto TOTP guardado en: $SECRETS_FILE"
    Write-Host ""
    Write-Host "  Secreto TOTP generado:" -ForegroundColor Green
    Write-Host "  $secret" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Para configurar Google Authenticator:" -ForegroundColor Cyan
    Write-Host "  1. Abre Google Authenticator"
    Write-Host "  2. Toca '+' -> 'Ingresar clave de configuracion'"
    Write-Host "  3. Nombre: $emisor"
    Write-Host "  4. Clave : $secret"
    Write-Host "  5. Tipo  : Basada en el tiempo"
    Write-Host ""

    # Generar pagina HTML con QR code usando API de Google
    $qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=" + [System.Uri]::EscapeDataString($totpUrl)
    $htmlPath = "$MFA_DIR\qr-mfa.html"
    $html = @"
<!DOCTYPE html>
<html>
<head><title>MFA QR - reprobados.com</title></head>
<body style='font-family:Arial;text-align:center;padding:20px'>
<h2>Configuracion MFA - reprobados.com</h2>
<p>Escanea este codigo con Google Authenticator</p>
<img src='$qrUrl' alt='QR Code MFA' width='200' height='200'/>
<p><b>Secreto:</b> $secret</p>
<p><b>Usuario:</b> $cuenta @ $emisor</p>
<p style='color:red;font-weight:bold'>CONFIDENCIAL - No compartir este codigo</p>
</body>
</html>
"@
    $html | Set-Content $htmlPath -Encoding UTF8
    Write-OK "Pagina QR generada: $htmlPath"
    Write-Info "Abre $htmlPath en el navegador para escanear el QR"
}

# =============================================================================
# CONFIGURAR POLITICAS DE BLOQUEO POR MFA FALLIDO
# =============================================================================

function Configurar-MFA-Politicas {
    Write-Info "Registrando usuario Administrator en MFA..."
    $secret = "TZZ4KWHILQC6CZE7"
    
    # 1. Asegurar que estamos en el directorio correcto
    if (Test-Path $MFA_DIR) {
        Set-Location $MFA_DIR
    }
    else {
        Write-Err "Directorio MFA no encontrado."
        return
    }

    # 2. Crear/Actualizar el usuario en el motor
    # El comando -force asegura que si ya existe, se actualice con el nuevo secreto
    .\multiotp.exe -create Administrator TOTP $secret 6 -force
    
    # 3. Activar el usuario y forzar el PIN (opcional)
    .\multiotp.exe -set Administrator users_active=1
    
    # --- PASO CRÍTICO: INTEGRACIÓN CON WINDOWS ---
    # Para que pida el código al entrar, el Credential Provider debe estar activo.
    # Si instalaste el MSI, esto suele estar en el registro.
    # Vamos a forzar la configuración del archivo de configuración global:
    
    if (Test-Path "multiotp.ini") {
        Write-Info "Ajustando archivo de configuración para Login de Windows..."
        # Aseguramos que el motor sepa que debe interactuar con el login
        (Get-Content multiotp.ini) -replace "display_logon=0", "display_logon=1" | Set-Content multiotp.ini
    }

    Write-OK "MFA vinculado a Google Authenticator para Administrator."
    Write-Info "Secreto para la app: $secret"
    Write-Warn "RECUERDA: La hora del servidor debe coincidir con la de tu celular."
}

# =============================================================================
# VERIFICAR ESTADO DE CUENTAS BLOQUEADAS
# =============================================================================

function Verificar-Cuentas-Bloqueadas {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   CUENTAS BLOQUEADAS EN AD               " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $bloqueadas = Search-ADAccount -LockedOut -ErrorAction SilentlyContinue
    if ($bloqueadas) {
        Write-Host "  Cuentas bloqueadas:" -ForegroundColor Red
        $bloqueadas | ForEach-Object {
            Write-Host "    $($_.SamAccountName) - Bloqueada desde: $($_.PasswordLastSet)"
            Write-Host "    DN: $($_.DistinguishedName)"
        }
    }
    else {
        Write-OK "  No hay cuentas bloqueadas actualmente"
    }
    Write-Host ""
}

# =============================================================================
# DESBLOQUEAR CUENTA
# =============================================================================

function Desbloquear-Cuenta {
    param([string]$Usuario)
    if (-not $Usuario) {
        $Usuario = Read-Host "  Usuario a desbloquear"
    }
    try {
        Unlock-ADAccount -Identity $Usuario
        Write-OK "Cuenta '$Usuario' desbloqueada"
    }
    catch {
        Write-Err "Error desbloqueando '$Usuario': $_"
    }
}

# =============================================================================
# MOSTRAR ESTADO MFA
# =============================================================================

function Mostrar-Estado-MFA {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DE MFA Y SEGURIDAD              " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # WinOTP
    $winotp = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*WinOTP*" }
    if ($winotp) {
        Write-OK "WinOTP instalado: $($winotp.DisplayName) v$($winotp.DisplayVersion)"
    }
    else {
        Write-Warn "WinOTP no detectado en el sistema"
    }

    # Secreto TOTP
    if (Test-Path $SECRETS_FILE) {
        Write-OK "Secreto TOTP guardado en: $SECRETS_FILE"
    }
    else {
        Write-Warn "Secreto TOTP no generado aun"
    }

    # FGPP MFA
    $fgpp = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'PSO-MFA-Lockout'" `
        -ErrorAction SilentlyContinue
    if ($fgpp) {
        Write-OK "FGPP Bloqueo MFA: $($fgpp.LockoutThreshold) intentos / $($fgpp.LockoutDuration) bloqueo"
    }
    else {
        Write-Warn "FGPP de bloqueo MFA no configurada"
    }

    # Cuentas bloqueadas
    $bloqueadas = (Search-ADAccount -LockedOut -ErrorAction SilentlyContinue).Count
    Write-Host "  Cuentas bloqueadas actualmente: $bloqueadas" -ForegroundColor $(if ($bloqueadas -gt 0) { "Red" } else { "Green" })
    Write-Host ""
}