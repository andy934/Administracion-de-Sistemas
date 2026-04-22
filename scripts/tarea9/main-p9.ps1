# =============================================================================
# main-p9.ps1 - Menu principal Practica 9
# Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# Suprimir warnings de verbos no aprobados durante carga
$WarningPreference = 'SilentlyContinue'
. "$ScriptDir\p9-func-utilidades.ps1"
. "$ScriptDir\p9-func-rbac.ps1"
. "$ScriptDir\p9-func-auditoria.ps1"
. "$ScriptDir\p9-func-mfa.ps1"
. "$ScriptDir\p9-func-tests.ps1"
$WarningPreference = 'Continue'

function Mostrar-Menu-P9 {
    Clear-Host
    Write-Host ""
    Write-Host "  +=========================================================+" -ForegroundColor Cyan
    Write-Host "  |   PRACTICA 9 - SEGURIDAD DE IDENTIDAD Y MFA            |" -ForegroundColor Cyan
    Write-Host "  |   Hardening AD, RBAC, FGPP, Auditoria, multiOTP        |" -ForegroundColor Cyan
    Write-Host "  +=========================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -- MFA (multiOTP) ---------------------------------------" -ForegroundColor Cyan
    Write-Host "   1. Preparar entorno y descargar multiOTP"
    Write-Host ""
    Write-Host "  -- RBAC y DELEGACION ------------------------------------" -ForegroundColor Cyan
    Write-Host "   2. Crear 4 usuarios administradores delegados"
    Write-Host "   3. Aplicar permisos RBAC (delegacion por ACL)"
    Write-Host ""
    Write-Host "  -- DIRECTIVAS Y AUDITORIA --------------------------------" -ForegroundColor Cyan
    Write-Host "   4. Configurar FGPP (12 chars admin / 8 chars usuario)"
    Write-Host "   5. Configurar auditoria + generar reporte ID 4625"
    Write-Host ""
    Write-Host "  -- MFA INSTALACION Y ACTIVACION -------------------------" -ForegroundColor Cyan
    Write-Host "   6. Instalar VC++ 2022 y multiOTP Credential Provider"
    Write-Host "   7. Activar MFA y generar secreto TOTP"
    Write-Host ""
    Write-Host "  -- PROTOCOLO DE PRUEBAS ---------------------------------" -ForegroundColor Cyan
    Write-Host "   8. Ejecutar tests automatizados (Tests 1-5)"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host ""
    Write-Host "  ---------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

while ($true) {
    Mostrar-Menu-P9
    $op = Read-Host "  Seleccione opcion (0-8)"
    Write-Host ""

    switch ($op) {
        "1" { Preparar-EntornoMFA }
        "2" { Crear-UsuariosAdmin }
        "3" { Aplicar-PermisosRBAC }
        "4" { Configurar-FGPP }
        "5" { Configurar-Auditoria }
        "6" { Instalar-MFA }
        "7" { Activar-MFA }
        "8" { Ejecutar-Tests }
        "0" { Write-Host ""; Write-Host "  Saliendo." -ForegroundColor Green; exit 0 }
        default { Write-Host "  Opcion invalida." -ForegroundColor Red }
    }
}
