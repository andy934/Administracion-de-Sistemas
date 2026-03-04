# ============================================================
#   ftp-config.ps1
#   Menu principal — Automatizacion de servidor FTP con IIS
#   Uso: .\ftp-config.ps1   (como Administrador)
# ============================================================

# Importar modulos
. .\configuracion.ps1
. .\alta-baja.ps1

# ── Verificar que se ejecuta como Administrador ───────────────
$esAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $esAdmin) {
    Write-Host "[ADVERTENCIA] Este script requiere privilegios de Administrador." -ForegroundColor Yellow
    Write-Host "Ejecute PowerShell como Administrador y vuelva a correr el script." -ForegroundColor Yellow
    Write-Host ""
}

# ── Menu ──────────────────────────────────────────────────────
function Mostrar-Menu {
    Clear-Host
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "      AUTOMATIZACION DE SERVIDOR FTP - IIS WINDOWS"         -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "-- 1.  Instalar y Configurar IIS + FTP Service          --"
    Write-Host "-- 2.  Ver estado del servicio FTP                      --"
    Write-Host "-- 3.  Alta de Usuario FTP                              --"
    Write-Host "-- 4.  Alta Masiva de Usuarios FTP                      --"
    Write-Host "-- 5.  Baja de Usuario FTP                              --"
    Write-Host "-- 6.  Cambio de grupo del Usuario FTP                  --"
    Write-Host "-- 7.  Listar Usuarios FTP registrados                  --"
    Write-Host "-- 8.  Ver permisos de un Usuario FTP                   --"
    Write-Host "-- 9.  Reiniciar el servicio FTP                        --"
    Write-Host "-- 10. Ver logs del servicio                            --"
    Write-Host "-- 11. Probar conexion FTP                              --"
    Write-Host "-- 12. Salir                                            --"
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ── Loop principal ────────────────────────────────────────────
while ($true) {
    Mostrar-Menu
    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        "1"  { Instalar-IIS-FTP }
        "2"  { Ver-Estado-Servicio }
        "3"  { Alta-Usuario }
        "4"  { Alta-Masiva-Usuarios }
        "5"  { Baja-Usuario }
        "6"  { Cambiar-Grupo-Usuario }
        "7"  { Listar-Usuarios }
        "8"  { Ver-Permisos-Usuario }
        "9"  { Reiniciar-Servicio }
        "10" { Ver-Logs }
        "11" { Probar-Conexion }
        "12" { Write-Host "Saliendo..."; exit 0 }
        default {
            Write-Host "[ERROR] Opcion no valida. Seleccione del 1 al 12." -ForegroundColor Red
        }
    }

    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}
