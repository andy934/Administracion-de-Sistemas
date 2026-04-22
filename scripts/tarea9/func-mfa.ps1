# =============================================================================
# func-mfa.ps1 - MFA con WinOTP (TOTP / Google Authenticator)
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

$VCREDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$MULTIOTP_URL = "https://download.multiotp.net/multiotp_windows.zip"
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
# INSTALAR WINOTP
# =============================================================================

function Instalar-WinOTP {
    if (-not (Test-Path $MFA_DIR)) { New-Item -Path $MFA_DIR -ItemType Directory -Force }

    # --- PASO 1: INSTALAR VISUAL C++ (REQUERIDO PARA MULTIOTP) ---
    Write-Info "Verificando Visual C++ 2022 Redistributable..."
    $vcInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
    if (-not $vcInstalled) {
        Write-Warn "Visual C++ no encontrado. Descargando..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $VCREDIST_URL -OutFile "$MFA_DIR\vc_redist.x64.exe" -UseBasicParsing
            Write-Info "Instalando Visual C++ de forma silenciosa..."
            Start-Process -FilePath "$MFA_DIR\vc_redist.x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait
            Write-OK "Visual C++ instalado correctamente."
        }
        catch {
            Write-Err "No se pudo instalar Visual C++. Verifique la conexion a internet."
        }
    }
    else {
        Write-OK "Visual C++ ya esta presente."
    }

    # --- PASO 2: DESCARGAR E INSTALAR MULTIOTP ---
    Write-Info "Configurando motor multiOTP..."
    if (-not (Test-Path "$MFA_DIR\multiotp.exe")) {
        try {
            Invoke-WebRequest -Uri $MULTIOTP_URL -OutFile "$MFA_DIR\multiotp.zip" -UseBasicParsing
            Expand-Archive -Path "$MFA_DIR\multiotp.zip" -DestinationPath $MFA_DIR -Force
            # Mover archivos si quedaron en una subcarpeta 'windows'
            if (Test-Path "$MFA_DIR\windows\multiotp.exe") {
                Move-Item -Path "$MFA_DIR\windows\*" -Destination $MFA_DIR -Force
            }
            Write-OK "Motor multiOTP descargado."
        }
        catch {
            Write-Err "Error al descargar multiOTP."
            return
        }
    }

    # --- PASO 3: REGISTRAR CREDENTIAL PROVIDER ---
    # Esto es lo que hace que Windows pida el codigo al entrar
    Write-Info "Activando el prompt de MFA en el inicio de sesion..."
    # Importante: Para que pida el codigo, el usuario debe estar creado en multiOTP
    # y el CP debe estar registrado en el registro de Windows.
    # El instalador .msi suele hacer esto, si usas el portable (.exe), 
    # hay que registrar la DLL del Credential Provider manualmente.
    
    Write-Warn "Asegurese de ejecutar la opcion de 'Configurar MFA' para registrar al Administrador."
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
