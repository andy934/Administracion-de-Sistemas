# =============================================================================
# main-win.ps1 - Orquestador principal Practica 7 Windows
# Sistema: Windows Server 2022
# =============================================================================

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# Funciones de output
function Write-OK   { param($msg) Write-Host "[OK] $msg"    -ForegroundColor Green  }
function Write-Info { param($msg) Write-Host "[INFO] $msg"  -ForegroundColor Cyan   }
function Write-Warn { param($msg) Write-Host "[WARN] $msg"  -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red    }

# Cargar modulos
. "$ScriptDir\func-repo-win.ps1"
. "$ScriptDir\func-ssl-win.ps1"
. "$ScriptDir\func-install-win.ps1"

# =============================================================================
# INDICADORES DE ESTADO
# =============================================================================

function Get-Icono-Svc {
    param([string]$Nombre)
    $svc = Get-Service $Nombre -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { return "[ON]" } else { return "[--]" }
}

function Get-Icono-Nginx {
    if (Get-Process nginx -ErrorAction SilentlyContinue) { return "[ON]" } else { return "[--]" }
}

function Get-Icono-Cert {
    if (Cert-Existe) { return "[OK]" } else { return "[--]" }
}

function Get-Icono-Repo {
    if (Repo-Esta-Listo) { return "[OK]" } else { return "[--]" }
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

function Mostrar-Menu {
    Clear-Host
    $iIIS    = Get-Icono-Svc "W3SVC"
    $iApache = Get-Icono-Svc "Apache"
    $iNginx  = Get-Icono-Nginx
    $iCert   = Get-Icono-Cert
    $iRepo   = Get-Icono-Repo

    Write-Host ""
    Write-Host "  +========================================================+" -ForegroundColor Cyan
    Write-Host "  |   PRACTICA 7 - DESPLIEGUE SEGURO E INSTALACION        |" -ForegroundColor Cyan
    Write-Host "  |   HIBRIDA  (FTP/WEB)  +  SSL/TLS                      |" -ForegroundColor Cyan
    Write-Host "  |   Sistema: Windows Server 2022                         |" -ForegroundColor Cyan
    Write-Host "  +========================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Estado actual:" -ForegroundColor White
    Write-Host "   $iIIS IIS   $iApache Apache   $iNginx Nginx"
    Write-Host "   $iCert Certificado SSL    $iRepo Repositorio FTP"
    Write-Host ""
    Write-Host "  -- REPOSITORIO FTP ----------------------------------" -ForegroundColor Cyan
    Write-Host "   1. Preparar repositorio FTP  (descargar binarios + sha256)"
    Write-Host "   2. Ver estado del repositorio"
    Write-Host ""
    Write-Host "  -- INSTALACION DE SERVIDORES ------------------------" -ForegroundColor Cyan
    Write-Host "   3. Instalar / reconfigurar IIS      (WEB o FTP + SSL)"
    Write-Host "   4. Instalar / reconfigurar Apache   (WEB o FTP + SSL)"
    Write-Host "   5. Instalar / reconfigurar Nginx    (WEB o FTP + SSL)"
    Write-Host ""
    Write-Host "  -- SSL/TLS ------------------------------------------" -ForegroundColor Cyan
    Write-Host "   6. Generar certificado SSL  (reprobados.com)"
    Write-Host "   7. Activar SSL en IIS"
    Write-Host "   8. Activar SSL en Apache"
    Write-Host "   9. Activar SSL en Nginx"
    Write-Host "  10. Activar FTPS en IIS-FTP"
    Write-Host "  11. Verificacion completa SSL"
    Write-Host ""
    Write-Host "  -- UTILIDADES ---------------------------------------" -ForegroundColor Cyan
    Write-Host "  12. Ver estado de todos los servicios"
    Write-Host "  13. Configuracion SSL completa (servidores ya instalados)"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Nota: cada opcion valida sus dependencias automaticamente" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# OPCION 13: SSL EN SERVIDORES YA INSTALADOS
# =============================================================================

function SSL-Completo-Existentes {
    Write-Host ""
    Write-Warn "Configurara SSL en IIS, Apache, Nginx e IIS-FTP"
    $confirm = Read-Host "  Continuar? [s/N]"
    if ($confirm -notmatch '^[sS]$') { return }

    Write-Host ""; Write-Info "=== PASO 1/5: Certificado SSL ==="
    Generar-Certificado

    Write-Host ""; Write-Info "=== PASO 2/5: SSL en IIS ==="
    $ph = Read-Host "  Puerto HTTPS [443]"
    SSL-IIS -PuertoHTTP $script:PuertoIIS -PuertoHTTPS $(if ($ph) { [int]$ph } else { 443 })

    Write-Host ""; Write-Info "=== PASO 3/5: SSL en Apache ==="
    $ph = Read-Host "  Puerto HTTPS [453]"
    SSL-Apache -PuertoHTTP $script:PuertoApacheHTTP -PuertoHTTPS $(if ($ph) { [int]$ph } else { 453 })

    Write-Host ""; Write-Info "=== PASO 4/5: SSL en Nginx ==="
    $ph = Read-Host "  Puerto HTTPS [454]"
    SSL-Nginx -PuertoHTTP $script:PuertoNginxHTTP -PuertoHTTPS $(if ($ph) { [int]$ph } else { 454 })

    Write-Host ""; Write-Info "=== PASO 5/5: FTPS en IIS-FTP ==="
    SSL-IISFTP

    Write-Host ""
    Resumen-SSL
    Ver-Estado-Servicios
    Write-OK "Configuracion SSL completa finalizada."
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

while ($true) {
    Mostrar-Menu
    $opcion = Read-Host "  Seleccione opcion (0-13)"
    Write-Host ""

    switch ($opcion) {
        "1"  { Preparar-Repositorio-Completo }
        "2"  { Mostrar-Estado-Repo }
        "3"  { Instalar-Servicio-Completo "iis"    }
        "4"  { Instalar-Servicio-Completo "apache" }
        "5"  { Instalar-Servicio-Completo "nginx"  }
        "6"  { Generar-Certificado }
        "7"  {
            Validar-Cert | Out-Null
            $ph = Read-Host "  Puerto HTTPS [443]"
            SSL-IIS -PuertoHTTP $script:PuertoIIS -PuertoHTTPS $(if ($ph) { [int]$ph } else { 443 })
        }
        "8"  {
            Validar-Cert | Out-Null
            $ph = Read-Host "  Puerto HTTPS [453]"
            SSL-Apache -PuertoHTTP $script:PuertoApacheHTTP -PuertoHTTPS $(if ($ph) { [int]$ph } else { 453 })
        }
        "9"  {
            Validar-Cert | Out-Null
            $ph = Read-Host "  Puerto HTTPS [454]"
            SSL-Nginx -PuertoHTTP $script:PuertoNginxHTTP -PuertoHTTPS $(if ($ph) { [int]$ph } else { 454 })
        }
        "10" { Validar-Cert | Out-Null; SSL-IISFTP }
        "11" { Resumen-SSL }
        "12" { Ver-Estado-Servicios }
        "13" { SSL-Completo-Existentes }
        "0"  { Write-Host ""; Write-OK "Saliendo."; exit 0 }
        default { Write-Warn "Opcion invalida: $opcion" }
    }

    Write-Host ""
    Read-Host "  Presiona ENTER para continuar"
}