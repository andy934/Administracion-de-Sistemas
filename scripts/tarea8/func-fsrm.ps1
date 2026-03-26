# =============================================================================
# func-fsrm.ps1 - FSRM: Cuotas de disco y File Screening
# Practica 8 - Administracion de Sistemas
# Sistema: Windows Server 2022
# =============================================================================

$USERS_BASE = "C:\Usuarios"
$QUOTA_CUATES    = 10MB   # 10 MB para Cuates
$QUOTA_NOCUATES  = 5MB    # 5 MB para No Cuates

# =============================================================================
# INSTALAR FSRM
# =============================================================================

function Instalar-FSRM {
    Write-Info "Verificando instalacion de FSRM..."

    $feature = Get-WindowsFeature FS-Resource-Manager -ErrorAction SilentlyContinue
    if ($feature -and $feature.Installed) {
        Write-Info "FSRM ya esta instalado"
        return $true
    }

    Write-Info "Instalando File Server Resource Manager..."
    $result = Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools

    if ($result.Success) {
        Write-OK "FSRM instalado correctamente"
        # Importar modulo
        Import-Module FileServerResourceManager -ErrorAction SilentlyContinue
        return $true
    } else {
        Write-Err "Fallo la instalacion de FSRM"
        return $false
    }
}

function Validar-FSRM {
    if ((Get-WindowsFeature FS-Resource-Manager -ErrorAction SilentlyContinue).Installed) {
        Import-Module FileServerResourceManager -ErrorAction SilentlyContinue
        return $true
    }
    Write-Warn "FSRM no esta instalado"
    $r = Read-Host "  Instalar FSRM ahora? [S/n]"
    if ($r -match '^[nN]$') { return $false }
    return (Instalar-FSRM)
}

# =============================================================================
# CREAR PLANTILLAS DE CUOTA
# =============================================================================

function Crear-Plantillas-Cuota {
    if (-not (Validar-FSRM)) { return }
    Write-Info "Creando plantillas de cuota..."

    try {
        # 1. Plantilla para Cuates (10 MB = 10485760 bytes)
        $nameCuates = "P8-Cuota-Cuates"
        if (-not (Get-FsrmQuotaTemplate -Name $nameCuates -ErrorAction SilentlyContinue)) {
            # Usamos el parámetro -Size expresado en bytes directamente
            New-FsrmQuotaTemplate -Name $nameCuates -Size 10485760
            Write-OK "Plantilla '$nameCuates' creada (10 MB)"
        } else {
            Write-Info "La plantilla '$nameCuates' ya existe"
        }

        # 2. Plantilla para No Cuates (5 MB = 5242880 bytes)
        $nameNoCuates = "P8-Cuota-NoCuates"
        if (-not (Get-FsrmQuotaTemplate -Name $nameNoCuates -ErrorAction SilentlyContinue)) {
            New-FsrmQuotaTemplate -Name $nameNoCuates -Size 5242880
            Write-OK "Plantilla '$nameNoCuates' creada (5 MB)"
        } else {
            Write-Info "La plantilla '$nameNoCuates' ya existe"
        }
    }
    catch {
        Write-Warn "Error crítico al crear plantillas FSRM: $($_.Exception.Message)"
    }
}

# =============================================================================
# APLICAR CUOTAS POR USUARIO
# =============================================================================

function Aplicar-Cuotas {
    if (-not (Validar-FSRM)) { return }
    if (-not (Validar-AD))   { return }

    Write-Info "Aplicando cuotas por usuario..."
    Write-Host ""

    $grupos = @(
        @{ Grupo = "GrupoCuates";   Plantilla = "P8-Cuota-Cuates";   MB = 10 },
        @{ Grupo = "GrupoNoCuates"; Plantilla = "P8-Cuota-NoCuates"; MB = 5  }
    )

    foreach ($g in $grupos) {
        $miembros = Get-ADGroupMember -Identity $g.Grupo -ErrorAction SilentlyContinue |
                    Where-Object { $_.objectClass -eq 'user' }

        if (-not $miembros) {
            Write-Warn "No hay miembros en $($g.Grupo)"
            continue
        }

        Write-Info "Aplicando cuota $($g.MB)MB a $($g.Grupo) ($($miembros.Count) usuarios)..."

        foreach ($u in $miembros) {
            $userPath = "$USERS_BASE\$($u.SamAccountName)"

            # Crear carpeta si no existe
            if (-not (Test-Path $userPath)) {
                New-Item -ItemType Directory -Path $userPath -Force | Out-Null
                Write-Info "  Carpeta creada: $userPath"
            }

            # Aplicar cuota
            $existing = Get-FsrmQuota -Path $userPath -ErrorAction SilentlyContinue
            if ($existing) {
                # 1. Si ya existe, la borramos para evitar errores de parámetros no encontrados
                Remove-FsrmQuota -Path $userPath -Confirm:$false -ErrorAction SilentlyContinue
            }

            # 2. Creamos la cuota (tanto si era nueva como si la acabamos de borrar)
            New-FsrmQuota -Path $userPath -Template $g.Plantilla
            Write-OK "  Cuota aplicada/actualizada: $($u.SamAccountName) -> $($g.MB)MB"
        }
        Write-Host ""
    }
    Write-OK "Cuotas aplicadas correctamente"
}

# =============================================================================
# FILE SCREENING: BLOQUEAR ARCHIVOS MULTIMEDIA Y EJECUTABLES
# =============================================================================

function Configurar-FileScreening {
    if (-not (Validar-FSRM)) { return }
    Write-Info "Configurando File Screening (bloqueo de archivos)..."

    try {
        $groupName = "P8-Archivos-Bloqueados"
        $templateName = "P8-FileScreen-Template"

        # 1. Crear el grupo de archivos (Filtro de extensiones)
        if (-not (Get-FsrmFileGroup -Name $groupName -ErrorAction SilentlyContinue)) {
            $extensiones = @("*.mp3", "*.mp4", "*.avi", "*.mkv", "*.mov", "*.wmv", "*.exe", "*.msi", "*.bat", "*.cmd", "*.com")
            New-FsrmFileGroup -Name $groupName -IncludePattern $extensiones
            Write-OK "Grupo de archivos '$groupName' creado."
        }

        # 2. Crear la Plantilla de Bloqueo
        # IMPORTANTE: Se especifica -Active explícitamente para evitar el error de posición
        if (-not (Get-FsrmFileScreenTemplate -Name $templateName -ErrorAction SilentlyContinue)) {
            New-FsrmFileScreenTemplate -Name $templateName `
                -IncludeGroup $groupName `
                -Active `
                -Description "Bloqueo P8: Multimedia y Ejecutables"
            Write-OK "Plantilla '$templateName' creada correctamente."
        }

        # 3. Aplicar el bloqueo a las carpetas de los usuarios
        Write-Info "Vinculando File Screen a carpetas en $USERS_BASE..."
        $carpetas = Get-ChildItem -Path $USERS_BASE -Directory
        
        foreach ($dir in $carpetas) {
            $rutaFolder = $dir.FullName
            # Verificamos si la carpeta ya tiene un bloqueo aplicado para evitar errores de duplicado
            if (-not (Get-FsrmFileScreen -Path $rutaFolder -ErrorAction SilentlyContinue)) {
                New-FsrmFileScreen -Path $rutaFolder -Template $templateName
                Write-OK "Bloqueo aplicado a: $($dir.Name)"
            }
        }
        Write-OK "Configuracion de File Screening finalizada."

    } catch {
        Write-Warn "Error critico en File Screening: $($_.Exception.Message)"
    }
}

# =============================================================================
# MOSTRAR ESTADO FSRM
# =============================================================================

function Mostrar-Estado-FSRM {
    if (-not (Validar-FSRM)) { return }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DE FSRM                         " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Cuotas
    Write-Host "  Cuotas configuradas:" -ForegroundColor White
    $cuotas = Get-FsrmQuota -ErrorAction SilentlyContinue
    if ($cuotas) {
        $cuotas | ForEach-Object {
            $usado = [math]::Round($_.Usage / 1MB, 2)
            $total = [math]::Round($_.Size / 1MB, 0)
            $pct   = if ($_.Size -gt 0) { [math]::Round($_.Usage * 100 / $_.Size, 0) } else { 0 }
            Write-Host "    $($_.Path) : $usado MB / $total MB ($pct%)"
        }
    } else {
        Write-Host "    No hay cuotas configuradas"
    }

    Write-Host ""
    Write-Host "  File Screens:" -ForegroundColor White
    $screens = Get-FsrmFileScreen -ErrorAction SilentlyContinue
    if ($screens) {
        $screens | ForEach-Object {
            $tipo = if ($_.Active) { "[ACTIVO]" } else { "[PASIVO]" }
            Write-Host "    $tipo $($_.Path)"
        }
    } else {
        Write-Host "    No hay file screens configurados"
    }
    Write-Host ""
}
