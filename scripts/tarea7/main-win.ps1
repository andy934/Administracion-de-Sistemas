# =============================================================================
# main-win.ps1 - Orquestador principal Practica 7 Windows
# Infraestructura de Despliegue Seguro e Instalacion Hibrida (FTP/Web)
# Sistema: Windows Server 2022
# =============================================================================

# Verificar Administrador
if (-not ([Security.Principal.WindowsPrincipal]
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Ejecutar como Administrador" -ForegroundColor Red
    exit 1
}

$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent

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
    if ($svc -and $svc.Status -eq 'Running') { return "[ON] " } else { return "[--] " }
}

function Get-Icono-Nginx {
    if (Get-Process nginx -ErrorAction SilentlyContinue) { return "[ON] " } else { return "[--] " }
}

function Get-Icono-Cert {
    if (Cert-Existe) { return "[OK] " } else { return "[--] " }
}

function Get-Icono-Repo {
    if (Repo-Esta-Listo) { return "[OK] " } else { return "[--] " }
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
    Write-Host "  +=======================================================+" -ForegroundColor Cyan
    Write-Host "  |   PRACTICA 7 - DESPLIEGUE SEGURO E INSTALACION       |" -ForegroundColor Cyan
    Write-Host "  |   HIBRIDA  (FTP/WEB)  +  SSL/TLS                     |" -ForegroundColor Cyan
    Write-Host "  |   Sistema: Windows Server 2022                        |" -ForegroundColor Cyan
    Write-Host "  +=======================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Estado actual:" -ForegroundColor White
    Write-Host "   ${iIIS}IIS   ${iApache}Apache   ${iNginx}Nginx"
    Write-Host "   ${iCert}Certificado SSL    ${iRepo}Repositorio FTP"
    Write-Host ""
    Write-Host "  -- REPOSITORIO FTP ---------------------------------" -ForegroundColor Cyan
    Write-Host "   1. Preparar repositorio FTP  (descargar binarios + sha256)"
    Write-Host "   2. Ver estado del repositorio"
    Write-Host ""
    Write-Host "  -- INSTALACION DE SERVIDORES -----------------------" -ForegroundColor Cyan
    Write-Host "   3. Instalar / reconfigurar IIS      (WEB o FTP + SSL opcional)"
    Write-Host "   4. Instalar / reconfigurar Apache   (WEB o FTP + SSL opcional)"
    Write-Host "   5. Instalar / reconfigurar Nginx    (WEB o FTP + SSL opcional)"
    Write-Host ""
    Write-Host "  -- SSL/TLS ------------------------------------------" -ForegroundColor Cyan
    Write-Host "   6. Generar certificado SSL  (reprobados.com)"
    Write-Host "   7. Activar SSL en IIS"
    Write-Host "   8. Activar SSL en Apache"
    Write-Host "   9. Activar SSL en Nginx"
    Write-Host "  10. Activar FTPS en IIS-FTP"
    Write-Host "  11. Verificacion completa SSL  (resumen de 4 servicios)"
    Write-Host ""
    Write-Host "  -- UTILIDADES ---------------------------------------" -ForegroundColor Cyan
    Write-Host "  12. Ver estado de todos los servicios"
    Write-Host "  13. Configuracion SSL completa  (solo SSL, servidores ya instalados)"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Nota: cada opcion valida sus dependencias automaticamente" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# OPCION 13: SSL COMPLETO EN SERVIDORES YA INSTALADOS (caso de uso principal)
# =============================================================================

function SSL-Completo-Existentes {
    Write-Host ""
    Write-Warn "Esto configurara SSL en IIS, Apache, Nginx e IIS-FTP"
    Write-Warn "Los servidores deben estar ya instalados (de Practica 6)"
    Write-Host ""
    $confirm = Read-Host "  Continuar? [s/N]"
    if ($confirm -notmatch '^[sS]$') { return }

    # Paso 1: Certificado
    Write-Host ""
    Write-Info "=== PASO 1/5: Certificado SSL ==="
    Generar-Certificado

    # Paso 2: IIS HTTPS
    Write-Host ""
    Write-Info "=== PASO 2/5: SSL en IIS ==="
    $ph = Read-Host "  Puerto HTTPS para IIS [443]"
    SSL-IIS -PuertoHTTP $script:PuertoIIS `
            -PuertoHTTPS $(if ($ph) { [int]$ph } else { 443 })

    # Paso 3: Apache HTTPS
    Write-Host ""
    Write-Info "=== PASO 3/5: SSL en Apache ==="
    $ph = Read-Host "  Puerto HTTPS para Apache [453]"
    SSL-Apache -PuertoHTTP $script:PuertoApacheHTTP `
               -PuertoHTTPS $(if ($ph) { [int]$ph } else { 453 })

    # Paso 4: Nginx HTTPS
    Write-Host ""
    Write-Info "=== PASO 4/5: SSL en Nginx ==="
    $ph = Read-Host "  Puerto HTTPS para Nginx [454]"
    SSL-Nginx -PuertoHTTP $script:PuertoNginxHTTP `
              -PuertoHTTPS $(if ($ph) { [int]$ph } else { 454 })

    # Paso 5: FTPS
    Write-Host ""
    Write-Info "=== PASO 5/5: FTPS en IIS-FTP ==="
    SSL-IISFTP

    # Resumen
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
            $ph = Read-Host "  Puerto HTTPS para IIS [443]"
            SSL-IIS -PuertoHTTP $script:PuertoIIS `
                    -PuertoHTTPS $(if ($ph) { [int]$ph } else { 443 })
        }
        "8"  {
            Validar-Cert | Out-Null
            $ph = Read-Host "  Puerto HTTPS para Apache [453]"
            SSL-Apache -PuertoHTTP $script:PuertoApacheHTTP `
                       -PuertoHTTPS $(if ($ph) { [int]$ph } else { 453 })
        }
        "9"  {
            Validar-Cert | Out-Null
            $ph = Read-Host "  Puerto HTTPS para Nginx [454]"
            SSL-Nginx -PuertoHTTP $script:PuertoNginxHTTP `
                      -PuertoHTTPS $(if ($ph) { [int]$ph } else { 454 })
        }
        "10" {
            Validar-Cert | Out-Null
            SSL-IISFTP
        }
        "11" { Resumen-SSL }
        "12" { Ver-Estado-Servicios }
        "13" { SSL-Completo-Existentes }
        "0"  {
            Write-Host ""
            Write-OK "Saliendo."
            exit 0
        }
        default { Write-Warn "Opcion invalida: $opcion" }
    }

    Write-Host ""
    Read-Host "  Presiona ENTER para continuar"
}
