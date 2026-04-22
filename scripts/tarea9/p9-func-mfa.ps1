# =============================================================================
# func-mfa.ps1 - MFA con multiOTP y TOTP
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# =============================================================================

function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PREPARAR ENTORNO Y DESCARGAR MFA       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    #$rutaDescarga = "C:\MFA_Setup"
    $rutaDescarga = "$env:TEMP\MFA_Setup"
    if (-not (Test-Path $rutaDescarga)) { New-Item $rutaDescarga -ItemType Directory }
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    $proceder = $true
    $existentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue
    if ($existentes) {
        Write-Host "  [AVISO] Ya hay archivos multiOTP en $rutaDescarga." -ForegroundColor Yellow
        $r = Read-Host "  Descargar la version mas nueva desde GitHub? (s/n)"
        if ($r.ToLower() -ne 's') { $proceder = $false; Write-Host "  [OK] Usando archivos existentes." -ForegroundColor Green }
    }

    if ($proceder) {
        Write-Host "  [INFO] Consultando GitHub API..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            $headers = @{ "User-Agent" = "PowerShell-P09" }
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest" -Headers $headers -UseBasicParsing
            $asset = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1
            if (-not $asset) { Write-Host "  [ERROR] Sin instalador en el release." -ForegroundColor Red; Read-Host | Out-Null; return }
            $rutaArchivo = "$rutaDescarga\$($asset.name)"
            Write-Host "  [INFO] Descargando $($release.tag_name) ($($asset.name))..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $rutaArchivo -UseBasicParsing -Headers $headers
            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Extrayendo ZIP..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
            }
            Write-Host "  [OK] Descarga completa." -ForegroundColor Green
        }
        catch {
            Write-Host "  [ERROR] Fallo la descarga: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 2: Crear los 4 usuarios + habilitar logon local
# ------------------------------------------------------------

function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   INSTALAR DEPENDENCIAS Y MOTOR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    #$rutaDescarga = "C:\MFA_Setup"
    $rutaDescarga = "$env:TEMP\MFA_Setup"
    if (-not (Test-Path $rutaDescarga)) { New-Item $rutaDescarga -ItemType Directory }
    $multiotpExe = Get-MultiOTPExe
    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP ya instalado: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $r = Read-Host "  Reconfigurar? (s/n)"
        if ($r.ToLower() -ne 's') { Write-Host "  Ve a la Opcion 7." -ForegroundColor Yellow; Read-Host | Out-Null; return }
    }

    Write-Host "  [1/2] Visual C++ 2022 Redistributable..." -ForegroundColor Yellow
    $vcPath = "$rutaDescarga\vc_redist_2022_x64.exe"
    if (-not (Test-Path $vcPath)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcPath -UseBasicParsing
        }
        catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red; Read-Host | Out-Null; return }
    }
    $p = Start-Process $vcPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($p.ExitCode -in @(0, 1638, 3010)) { Write-Host "  [OK] VC++ listo." -ForegroundColor Green }
    Start-Sleep -Seconds 2

    Write-Host "`n  [2/2] Instalador multiOTP..." -ForegroundColor Yellow
    Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = "$rutaDescarga\Extracted_$($_.BaseName)"
        if (-not (Test-Path $dest)) { Expand-Archive -Path $_.FullName -DestinationPath $dest -Force }
    }
    $instalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
    Sort-Object Length -Descending | Select-Object -First 1
    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro instalador. Ejecuta Opcion 1." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    Write-Host "`n  INSTRUCCIONES DEL INSTALADOR:" -ForegroundColor Yellow
    Write-Host "  1. Marca: 'No remote server, local multiOTP only'" -ForegroundColor White
    Write-Host "  2. Logon  -> 'Local and Remote'"                   -ForegroundColor White
    Write-Host "  3. Unlock -> 'Local and Remote'"                   -ForegroundColor White
    Write-Host "  4. Next hasta Finish."                             -ForegroundColor White
    Write-Host "  Presiona Enter para lanzar..."
    Read-Host | Out-Null
    try {
        if ($instalador.Extension -eq ".msi") { $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$($instalador.FullName)`"" -Wait -PassThru }
        else { $p = Start-Process $instalador.FullName -Wait -PassThru }
        if ($p.ExitCode -eq 0) { Write-Host "  [OK] multiOTP instalado." -ForegroundColor Green }
        else { Write-Host "  [AVISO] Codigo $($p.ExitCode)." -ForegroundColor Yellow }
    }
    catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 7: Registrar TODOS los admins en multiOTP
# ------------------------------------------------------------

function Activar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   ACTIVAR MFA Y GENERAR CLAVE TOTP       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $multiotpExe = Get-MultiOTPExe
    if (-not $multiotpExe) {
        Write-Host "  [ERROR] multiotp.exe no encontrado. Ejecuta Opcion 6." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    $dir = Split-Path $multiotpExe
    Push-Location $dir

    $netbios = $env:USERDOMAIN
    $dns = $env:USERDNSDOMAIN
    if ([string]::IsNullOrWhiteSpace($dns)) { $dns = (Get-ADDomain).DNSRoot }

    $base32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $miSecreto = -join ((1..16) | ForEach-Object { $base32[(Get-Random -Maximum 32)] })
    Write-Host "  [INFO] Secreto maestro: $miSecreto`n" -ForegroundColor DarkGray

    $usuarios = @("Administrator", "admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
    $totalOK = 0
    foreach ($u in $usuarios) {
        Write-Host "  Registrando: $u ..." -ForegroundColor Yellow
        foreach ($id in @($u, "$netbios\$u", "$u@$dns")) {
            & ".\multiotp.exe" -delete $id 2>&1 | Out-Null
            $s = & ".\multiotp.exe" -create $id TOTP $miSecreto 6 2>&1
            if ($s -match "(?i)(ok|success|created|0)") {
                Write-Host "    [OK] $id" -ForegroundColor Green; $totalOK++
            }
            else {
                Write-Host "    [WARN] $id -> $s" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`n  Configurando bloqueo (3 fallos = 30 min)..." -ForegroundColor Yellow
    & ".\multiotp.exe" -config MaxDelayedFailures=3       2>&1 | Out-Null
    & ".\multiotp.exe" -config MaxBlockFailures=3         2>&1 | Out-Null
    & ".\multiotp.exe" -config FailureDelayInSeconds=1800 2>&1 | Out-Null
    Write-Host "  [OK] Bloqueo configurado." -ForegroundColor Green
    Pop-Location

    $archivo = "C:\MFA_Setup\MFA_Secret_TodosAdmins.txt"
    @("MFA TOTP Secret - Practica 09", "==============================",
        "Usuarios : Administrator, admin_identidad, admin_storage, admin_politicas, admin_auditoria",
        "Servidor : $env:COMPUTERNAME", "Dominio  : $netbios ($dns)",
        "Secreto  : $miSecreto", "Tipo     : TOTP RFC 6238 (Google Authenticator)",
        "Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
        "", "NOTA: Todos los usuarios comparten el mismo secreto TOTP."
    ) | Out-File $archivo -Encoding UTF8

    Write-Host "`n  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |   ACTUALIZA GOOGLE AUTHENTICATOR                         |" -ForegroundColor Magenta
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  IMPORTANTE: Borra la entrada vieja y agrega una nueva:"      -ForegroundColor Red
    Write-Host ""
    Write-Host "     Nombre : Practica09 - $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "     Secreto: $miSecreto"                     -ForegroundColor Green
    Write-Host "     Tipo   : Basada en tiempo (TOTP)"        -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Sirve para TODOS: Administrator, admin_identidad, admin_storage," -ForegroundColor White
    Write-Host "  admin_politicas y admin_auditoria."                               -ForegroundColor White
    Write-Host "`n  [OK] Secreto guardado en: $archivo"                            -ForegroundColor Green
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 8: Ejecutar tests automatizados
# ------------------------------------------------------------

