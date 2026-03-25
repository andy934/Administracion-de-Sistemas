# =============================================================================
# main-client-win.ps1 - Unir cliente Windows al dominio reprobados.com
# Practica 8 - Administracion de Sistemas
# Sistema: Windows 10/11 cliente
# =============================================================================

$DOMAIN      = "reprobados.com"
$DOMAIN_DC   = ""   # IP del servidor AD - se solicita al usuario
$ADMIN_USER  = "Administrador"

function Write-OK   { param($msg) Write-Host "[OK] $msg"    -ForegroundColor Green  }
function Write-Info { param($msg) Write-Host "[INFO] $msg"  -ForegroundColor Cyan   }
function Write-Warn { param($msg) Write-Host "[WARN] $msg"  -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red    }

# =============================================================================
# VERIFICAR SI YA ESTA EN EL DOMINIO
# =============================================================================

function En-Dominio {
    return (Get-WmiObject Win32_ComputerSystem).PartOfDomain
}

# =============================================================================
# CONFIGURAR DNS PARA APUNTAR AL DC
# =============================================================================

function Configurar-DNS-Cliente {
    param([string]$DCIP)

    Write-Info "Configurando DNS para apuntar al DC ($DCIP)..."
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($adapter) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
            -ServerAddresses @($DCIP, "8.8.8.8")
        Write-OK "DNS configurado: primario=$DCIP, secundario=8.8.8.8"
    } else {
        Write-Warn "No se encontro adaptador de red activo"
    }
}

# =============================================================================
# VERIFICAR CONECTIVIDAD CON EL DC
# =============================================================================

function Verificar-Conectividad {
    param([string]$DCIP)

    Write-Info "Verificando conectividad con el DC ($DCIP)..."

    if (Test-Connection -ComputerName $DCIP -Count 2 -Quiet) {
        Write-OK "DC accesible: $DCIP"
        return $true
    } else {
        Write-Err "No se puede alcanzar el DC: $DCIP"
        Write-Err "Verifica que el servidor este activo y en la misma red"
        return $false
    }
}

# =============================================================================
# UNIR AL DOMINIO
# =============================================================================

function Unir-Al-Dominio {
    Write-Host ""
    Write-Host "  +========================================================+" -ForegroundColor Cyan
    Write-Host "  |   UNION AL DOMINIO reprobados.com                      |" -ForegroundColor Cyan
    Write-Host "  |   Cliente Windows                                       |" -ForegroundColor Cyan
    Write-Host "  +========================================================+" -ForegroundColor Cyan
    Write-Host ""

    if (En-Dominio) {
        $currentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
        Write-Info "Este equipo ya pertenece al dominio: $currentDomain"
        return
    }

    # Solicitar IP del DC
    do {
        $DOMAIN_DC = Read-Host "  IP del servidor DC (ej. 192.168.1.10)"
    } while (-not $DOMAIN_DC)

    Configurar-DNS-Cliente -DCIP $DOMAIN_DC
    if (-not (Verificar-Conectividad -DCIP $DOMAIN_DC)) { return }

    # Solicitar credenciales del dominio
    Write-Info "Se necesitan credenciales del Administrador del dominio"
    $cred = Get-Credential -Message "Credenciales de $DOMAIN\$ADMIN_USER" `
            -UserName "$DOMAIN\$ADMIN_USER"

    if (-not $cred) {
        Write-Err "No se proporcionaron credenciales"
        return
    }

    # Nombre del equipo
    $currentName = $env:COMPUTERNAME
    Write-Info "Nombre actual del equipo: $currentName"
    $newName = Read-Host "  Nuevo nombre para el equipo (ENTER para mantener '$currentName')"
    if (-not $newName) { $newName = $currentName }

    Write-Info "Uniendo '$newName' al dominio '$DOMAIN'..."
    try {
        if ($newName -ne $currentName) {
            Add-Computer -DomainName $DOMAIN `
                -NewName $newName `
                -Credential $cred `
                -Restart -Force
        } else {
            Add-Computer -DomainName $DOMAIN `
                -Credential $cred `
                -Restart -Force
        }
        Write-OK "Equipo unido al dominio. Reiniciando..."
    } catch {
        Write-Err "Error al unirse al dominio: $_"
    }
}

# =============================================================================
# MAIN
# =============================================================================

# Verificar que se ejecuta como administrador
if (-not ([Security.Principal.WindowsPrincipal]
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Ejecutar como Administrador"
    exit 1
}

Unir-Al-Dominio
