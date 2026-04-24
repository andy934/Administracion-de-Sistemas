# =============================================================================
# main.ps1 - Orquestador principal Practica 9
# Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Write-OK { param($msg) Write-Host "[OK] $msg"    -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg"  -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host "[WARN] $msg"  -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Cargar modulos
. "$ScriptDir\func-rbac.ps1"
. "$ScriptDir\func-auditoria.ps1"
. "$ScriptDir\func-mfa.ps1"
. "$ScriptDir\func-perfiles.ps1"

# =============================================================================
# INDICADORES DE ESTADO
# =============================================================================

function Get-Icon-AD {
    try { Get-ADDomain -ErrorAction Stop | Out-Null; return "[OK]" } catch { return "[--]" }
}

function Get-Icon-Admins {
    try {
        $n = (Get-ADUser -Filter "SamAccountName -like 'admin_*'" -ErrorAction Stop).Count
        if ($n -ge 4) { return "[4 ]" } elseif ($n -gt 0) { return "[$n ]" } else { return "[--]" }
    }
    catch { return "[--]" }
}

function Get-Icon-FGPP {
    $n = (Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction SilentlyContinue).Count
    if ($n -gt 0) { return "[OK]" } else { return "[--]" }
}

function Get-Icon-MFA {
    if (Test-Path "C:\MFA\mfa-secrets.txt") { return "[OK]" } else { return "[--]" }
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

function Mostrar-Menu {
    Clear-Host
    $iAD = Get-Icon-AD
    $iAdm = Get-Icon-Admins
    $iFGPP = Get-Icon-FGPP
    $iMFA = Get-Icon-MFA

    Write-Host ""
    Write-Host "  +=========================================================+" -ForegroundColor Cyan
    Write-Host "  |   PRACTICA 9 - SEGURIDAD DE IDENTIDAD                   |" -ForegroundColor Cyan
    Write-Host "  |   Delegacion, RBAC, Auditoria y MFA                     |" -ForegroundColor Cyan
    Write-Host "  |   Sistema: Windows Server 2022                           |" -ForegroundColor Cyan
    Write-Host "  +=========================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Estado: $iAD AD   $iAdm Admins   $iFGPP FGPP   $iMFA MFA" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- DELEGACION DE CONTROL (RBAC) -------------------------" -ForegroundColor Cyan
    Write-Host "   1. Crear 4 usuarios administradores delegados"
    Write-Host "   2. Configurar delegacion completa (4 roles)"
    Write-Host "   3. Ver estado de roles RBAC"
    Write-Host ""
    Write-Host "  -- DIRECTIVAS DE CONTRASENA Y AUDITORIA -----------------" -ForegroundColor Cyan
    Write-Host "   4. Configurar FGPP (12 chars admin / 8 chars usuario)"
    Write-Host "   5. Habilitar auditoria de eventos (hardening)"
    Write-Host "   6. Generar reporte de accesos denegados"
    Write-Host "   7. Ver estado de auditoria y FGPP"
    Write-Host ""
    Write-Host "  -- MFA (Google Authenticator / TOTP) --------------------" -ForegroundColor Cyan
    Write-Host "   8. Instalar dependencias y motor MFA (multiOTP)"
    Write-Host "   9. Configurar politica de bloqueo (3 intentos/30 min)"
    Write-Host "  10. Ver cuentas bloqueadas"
    Write-Host "  11. Desbloquear cuenta"
    Write-Host "  12. Ver estado de MFA"
    Write-Host ""
    Write-Host "  -- UTILIDADES -------------------------------------------" -ForegroundColor Cyan
    Write-Host "  13. Configuracion completa (servidor limpio o actualizar)"
    Write-Host "  15. Configurar perfiles moviles"
    Write-Host "  14. Ejecutar script de reporte standalone"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host ""
    Write-Host "  ---------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Nota: cada opcion valida sus dependencias automaticamente" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# CONFIGURACION COMPLETA
# =============================================================================

function Configuracion-Completa-P9 {
    Write-Host ""
    Write-Warn "Esto configurara RBAC + FGPP + Auditoria + MFA"
    $confirm = Read-Host "  Continuar? [s/N]"
    if ($confirm -notmatch '^[sS]$') { return }

    Write-Host ""; Write-Info "=== PASO 1/5: Usuarios administradores delegados ==="
    Crear-Admins-Delegados

    Write-Host ""; Write-Info "=== PASO 2/5: Delegacion de control (4 roles) ==="
    Configurar-RBAC-Completo

    Write-Host ""; Write-Info "=== PASO 3/5: Fine-Grained Password Policies ==="
    Configurar-FGPP

    Write-Host ""; Write-Info "=== PASO 4/5: Hardening de auditoria ==="
    Configurar-Auditoria

    Write-Host ""; Write-Info "=== PASO 5/5: MFA (TOTP / Google Authenticator) ==="
    Instalar-MFA

    Write-Host ""
    Write-OK "Configuracion completa de Practica 9 finalizada."
    Write-Host ""
    Mostrar-Estado-RBAC
    Mostrar-Estado-Auditoria
    Mostrar-Estado-MFA
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

while ($true) {
    Mostrar-Menu
    $op = Read-Host "  Seleccione opcion (0-15)"
    Write-Host ""

    switch ($op) {
        "1" { Crear-Admins-Delegados }
        "2" { Configurar-RBAC-Completo }
        "3" { Mostrar-Estado-RBAC }
        "4" { Configurar-FGPP }
        "5" { Configurar-Auditoria }
        "6" { Generar-Reporte-Auditoria }
        "7" { Mostrar-Estado-Auditoria }
        "8" { Instalar-MFA }
        "9" { Configurar-MFA-Politicas }
        "10" { Verificar-Cuentas-Bloqueadas }
        "11" { Desbloquear-Cuenta }
        "12" { Mostrar-Estado-MFA }
        "13" { Configuracion-Completa-P9 }
        "15" { Configurar-PerfilesMoviles }
        "14" {
            $ruta = Read-Host "  Ruta del reporte [C:\Auditoria\reporte.txt]"
            if (-not $ruta) { $ruta = "C:\Auditoria\reporte.txt" }
            & "$ScriptDir\reporte-auditoria.ps1" -RutaSalida $ruta
        }
        "0" { Write-Host ""; Write-OK "Saliendo."; exit 0 }
        default { Write-Warn "Opcion invalida" }
    }

    Write-Host ""
    Read-Host "  Presiona ENTER para continuar"
}