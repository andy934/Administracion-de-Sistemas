# =============================================================================
# http-main.ps1 — Script principal (solo llamadas a funciones)
# Práctica 6 — Despliegue Dinámico de Servicios HTTP Multi-Version
# Sistema: Windows Server 2022
# =============================================================================

. .\http-func.ps1

function Mostrar-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     DESPLIEGUE DINÁMICO DE SERVICIOS HTTP            ║" -ForegroundColor Cyan
    Write-Host "  ║     Práctica 6 — Administración de Sistemas          ║" -ForegroundColor Cyan
    Write-Host "  ║     Windows Server 2022                              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Mostrar-Menu {
    Mostrar-Banner
    Ver-Estado-Servicios

    Write-Host "  ── Instalación ─────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "   1. Instalar IIS"
    Write-Host "   2. Instalar Apache HTTP Server"
    Write-Host "   3. Instalar Nginx"
    Write-Host ""
    Write-Host "  ── Administración ──────────────────────────────────" -ForegroundColor Yellow
    Write-Host "   4. Ver estado de servicios"
    Write-Host "   5. Cambiar puerto de un servicio"
    Write-Host "   6. Ver logs de un servicio"
    Write-Host "   7. Desinstalar un servicio"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host ""
}

function Main {
    # Verificar que se ejecuta como Administrador
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Write-Err "Este script debe ejecutarse como Administrador."
        exit 1
    }

    # Configurar política de ejecución
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

    while ($true) {
        Mostrar-Menu
        $opcion = Read-Host "  Seleccione una opcion"

        switch ($opcion) {
            "1" {
                $puerto = ""
                do {
                    $input = Read-Host "Puerto para IIS (ej. 80, 8080)"
                    if (Validar-Puerto -Puerto $input) { $puerto = $input }
                } while ([string]::IsNullOrEmpty($puerto))
                Instalar-IIS -Puerto ([int]$puerto)
            }
            "2" { Instalar-Apache-Win }
            "3" { Instalar-Nginx-Win }
            "4" { Ver-Estado-Servicios }
            "5" { Cambiar-Puerto-Servicio }
            "6" { Ver-Logs-Servicio }
            "7" { Desinstalar-Servicio }
            "0" { Write-Host ""; Write-Host "Saliendo..."; exit 0 }
            default { Write-Err "Opcion invalida." }
        }

        Write-Host ""
        Read-Host "  Presione ENTER para continuar"
    }
}

Main