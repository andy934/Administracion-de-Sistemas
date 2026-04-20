# =============================================================================
# func-mfa.ps1 - MFA con WinOTP (TOTP / Google Authenticator)
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

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
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   INSTALACION DE WinOTP (MFA/TOTP)       " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    if (Verificar-Prerequisitos-MFA) {
        Write-Info "WinOTP ya instalado. Continuando con configuracion..."
        Configurar-MFA-Politicas
        return
    }

    # Crear directorio
    New-Item -ItemType Directory -Force -Path $MFA_DIR | Out-Null

    Write-Info "Descargando WinOTP..."
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($WINOTP_URL, $WINOTP_MSI)
        Write-OK "WinOTP descargado: $WINOTP_MSI"
    }
    catch {
        Write-Warn "No se pudo descargar WinOTP automaticamente"
        Write-Warn "Descarga manual desde: https://github.com/nicowillis/WinOTP/releases"
        Write-Warn "Guarda el MSI en: $WINOTP_MSI"
        Write-Host ""
        Write-Host "  Alternativa: Usar el metodo manual de configuracion TOTP" -ForegroundColor Yellow
        Configurar-TOTP-Manual
        return
    }

    Write-Info "Instalando WinOTP..."
    $proc = Start-Process msiexec -ArgumentList "/i `"$WINOTP_MSI`" /quiet /norestart" `
        -Wait -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-OK "WinOTP instalado correctamente"
    }
    else {
        Write-Err "Error en instalacion de WinOTP (codigo: $($proc.ExitCode))"
        Write-Info "Intentando configuracion TOTP manual..."
        Configurar-TOTP-Manual
        return
    }

    Configurar-MFA-Politicas
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
    Write-Info "Configurando politicas de bloqueo por intentos MFA fallidos..."
    Write-Host ""

    $fgppMFA = "PSO-MFA-Lockout"
    
    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppMFA'" -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy `
            -Name                        $fgppMFA `
            -Precedence                  5 `
            -MinPasswordLength           12 `
            -PasswordHistoryCount        10 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -LockoutThreshold            3 `
            -LockoutDuration             "00:30:00" `
            -LockoutObservationWindow    "00:30:00" `
            -Description                 "P9 - Bloqueo MFA: 3 intentos / 30 min"

        Write-OK "FGPP MFA creada: 3 intentos -> bloqueo 30 minutos"
    }
    else {
        Write-Info "FGPP '$fgppMFA' ya existe"
    }

    # Aplicar a todos los administradores delegados y al Administrador
    $admins = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria", "Administrador")
    foreach ($admin in $admins) {
        Add-ADFineGrainedPasswordPolicySubject `
            -Identity $fgppMFA -Subjects $admin -ErrorAction SilentlyContinue
    }
    
    Write-OK "Politica de bloqueo MFA aplicada a usuarios admin"
    Write-Host ""
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
