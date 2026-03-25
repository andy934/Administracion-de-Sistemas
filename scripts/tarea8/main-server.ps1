# =============================================================================
# main-server.ps1 - Orquestador principal Practica 8 (Servidor)
# GPO + FSRM + Active Directory
# Sistema: Windows Server 2022
# =============================================================================

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Write-OK   { param($msg) Write-Host "[OK] $msg"    -ForegroundColor Green  }
function Write-Info { param($msg) Write-Host "[INFO] $msg"  -ForegroundColor Cyan   }
function Write-Warn { param($msg) Write-Host "[WARN] $msg"  -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red    }

# Cargar modulos
. "$ScriptDir\func-ad.ps1"
. "$ScriptDir\func-gpo.ps1"
. "$ScriptDir\func-fsrm.ps1"

# =============================================================================
# INDICADORES
# =============================================================================

function Get-Icon-AD {
    if (AD-Configurado) { return "[OK]" } else { return "[--]" }
}
function Get-Icon-FSRM {
    if ((Get-WindowsFeature FS-Resource-Manager -ErrorAction SilentlyContinue).Installed) {
        return "[OK]" } else { return "[--]" }
}
function Get-Icon-Usuarios {
    try {
        $n = (Get-ADUser -Filter * -SearchBase $DOMAIN_DN -ErrorAction SilentlyContinue).Count
        if ($n -gt 0) { return "[$n u]" } else { return "[--]" }
    } catch { return "[--]" }
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

function Mostrar-Menu {
    Clear-Host
    $iAD   = Get-Icon-AD
    $iFSRM = Get-Icon-FSRM
    $iUs   = Get-Icon-Usuarios

    Write-Host ""
    Write-Host "  +========================================================+" -ForegroundColor Cyan
    Write-Host "  |   PRACTICA 8 - GPO + FSRM + ACTIVE DIRECTORY          |" -ForegroundColor Cyan
    Write-Host "  |   Gestion de Recursos y Restriccion del Entorno        |" -ForegroundColor Cyan
    Write-Host "  |   Sistema: Windows Server 2022                         |" -ForegroundColor Cyan
    Write-Host "  +========================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Estado: $iAD AD   $iFSRM FSRM   $iUs Usuarios" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- ACTIVE DIRECTORY ---------------------------------" -ForegroundColor Cyan
    Write-Host "   1. Instalar AD DS y configurar dominio reprobados.com"
    Write-Host "   2. Crear OUs (Cuates y NoCuates)"
    Write-Host "   3. Crear grupos de seguridad"
    Write-Host "   4. Importar usuarios desde CSV"
    Write-Host "   5. Ver estado de AD"
    Write-Host ""
    Write-Host "  -- GPO: CONTROL DE ACCESO ---------------------------" -ForegroundColor Cyan
    Write-Host "   6. Configurar horarios de inicio de sesion (Logon Hours)"
    Write-Host "   7. Configurar GPO cierre de sesion automatico"
    Write-Host "   8. Configurar AppLocker (Notepad por grupo)"
    Write-Host "   9. Ver estado de GPOs"
    Write-Host ""
    Write-Host "  -- FSRM: ALMACENAMIENTO -----------------------------" -ForegroundColor Cyan
    Write-Host "  10. Instalar FSRM"
    Write-Host "  11. Crear plantillas de cuota (5MB y 10MB)"
    Write-Host "  12. Aplicar cuotas por usuario"
    Write-Host "  13. Configurar File Screening (bloqueo de archivos)"
    Write-Host "  14. Ver estado de FSRM"
    Write-Host ""
    Write-Host "  -- UTILIDADES ---------------------------------------" -ForegroundColor Cyan
    Write-Host "  15. Configuracion completa (servidor limpio)"
    Write-Host "  16. Generar CSV de ejemplo"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Nota: cada opcion valida sus dependencias automaticamente" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# GENERAR CSV DE EJEMPLO
# =============================================================================

function Generar-CSV-Ejemplo {
    $csvPath = "$ScriptDir\usuarios.csv"
    if (Test-Path $csvPath) {
        Write-Info "usuarios.csv ya existe en $csvPath"
        $r = Read-Host "  Sobrescribir? [s/N]"
        if ($r -notmatch '^[sS]$') { return }
    }

    $contenido = @"
Nombre,Apellido,Usuario,Contrasena,Departamento
Juan,Perez,jperez,Pass@2026,Cuates
Maria,Lopez,mlopez,Pass@2026,Cuates
Carlos,Garcia,cgarcia,Pass@2026,Cuates
Ana,Martinez,amartinez,Pass@2026,Cuates
Luis,Rodriguez,lrodriguez,Pass@2026,Cuates
Sofia,Hernandez,shernandez,Pass@2026,NoCuates
Diego,Gonzalez,dgonzalez,Pass@2026,NoCuates
Valeria,Torres,vtorres,Pass@2026,NoCuates
Miguel,Ramirez,mramirez,Pass@2026,NoCuates
Fernanda,Flores,fflores,Pass@2026,NoCuates
"@
    Set-Content $csvPath -Value $contenido -Encoding UTF8
    Write-OK "CSV generado en: $csvPath"
    Write-Info "5 usuarios en Cuates, 5 en NoCuates"
}

# =============================================================================
# CONFIGURACION COMPLETA (servidor limpio)
# =============================================================================

function Configuracion-Completa {
    Write-Host ""
    Write-Warn "Esto configurara todo desde cero en orden:"
    Write-Host "  1. Instalar AD DS + dominio"
    Write-Host "  2. Crear OUs y grupos"
    Write-Host "  3. Importar usuarios desde CSV"
    Write-Host "  4. Configurar Logon Hours + GPO cierre de sesion"
    Write-Host "  5. Configurar AppLocker"
    Write-Host "  6. Instalar FSRM + cuotas + file screening"
    Write-Host ""
    $confirm = Read-Host "  Continuar? [s/N]"
    if ($confirm -notmatch '^[sS]$') { return }

    Write-Host ""; Write-Info "=== PASO 1/6: Active Directory ==="
    Instalar-AD-Completo

    # Si hubo reinicio, los siguientes pasos se ejecutan despues
    if (-not (AD-Configurado)) {
        Write-Warn "AD no disponible aun. Ejecuta de nuevo tras el reinicio."
        return
    }

    Write-Host ""; Write-Info "=== PASO 2/6: OUs y Grupos ==="
    Crear-OUs
    Crear-Grupos

    Write-Host ""; Write-Info "=== PASO 3/6: Usuarios desde CSV ==="
    Crear-Usuarios-CSV

    Write-Host ""; Write-Info "=== PASO 4/6: Logon Hours + GPO ==="
    Configurar-LogonHours
    Configurar-GPO-LogonHours

    Write-Host ""; Write-Info "=== PASO 5/6: AppLocker ==="
    Configurar-AppLocker

    Write-Host ""; Write-Info "=== PASO 6/6: FSRM ==="
    Instalar-FSRM
    Crear-Plantillas-Cuota
    Aplicar-Cuotas
    Configurar-FileScreening

    Write-Host ""
    Write-OK "Configuracion completa del servidor finalizada."
    Write-Host ""
    Mostrar-Estado-AD
    Mostrar-Estado-FSRM
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

while ($true) {
    Mostrar-Menu
    $op = Read-Host "  Seleccione opcion (0-16)"
    Write-Host ""

    switch ($op) {
        "1"  { Instalar-AD-Completo }
        "2"  { Crear-OUs }
        "3"  { Crear-Grupos }
        "4"  { Crear-Usuarios-CSV }
        "5"  { Mostrar-Estado-AD }
        "6"  { Configurar-LogonHours }
        "7"  { Configurar-GPO-LogonHours }
        "8"  { Configurar-AppLocker }
        "9"  { Mostrar-Estado-GPO }
        "10" { Instalar-FSRM }
        "11" { Crear-Plantillas-Cuota }
        "12" { Aplicar-Cuotas }
        "13" { Configurar-FileScreening }
        "14" { Mostrar-Estado-FSRM }
        "15" { Configuracion-Completa }
        "16" { Generar-CSV-Ejemplo }
        "0"  { Write-Host ""; Write-OK "Saliendo."; exit 0 }
        default { Write-Warn "Opcion invalida" }
    }

    Write-Host ""
    Read-Host "  Presiona ENTER para continuar"
}
