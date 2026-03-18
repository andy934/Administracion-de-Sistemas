#!/usr/bin/env bash
# =============================================================================
# main.sh - Orquestador principal Practica 7
# Infraestructura de Despliegue Seguro e Instalacion Hibrida (FTP/Web)
# Sistema: Rocky Linux 9
# =============================================================================

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecutar como root: sudo bash main.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colores globales (disponibles para todos los modulos)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Cargar modulos
source "$SCRIPT_DIR/func-repo.sh"
source "$SCRIPT_DIR/func-ssl.sh"
source "$SCRIPT_DIR/func-install.sh"

# =============================================================================
# INDICADORES DE ESTADO PARA EL MENU
# =============================================================================

_icono_svc() {
    systemctl is-active "$1" &>/dev/null && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}"
}

_icono_cert() {
    cert_existe && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}"
}

_icono_repo() {
    repo_esta_listo && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}"
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

mostrar_menu() {
    clear
    local i_vsftpd i_apache i_nginx i_tomcat i_cert i_repo
    i_vsftpd=$(_icono_svc vsftpd)
    i_apache=$(_icono_svc httpd-custom)
    i_nginx=$(_icono_svc nginx-custom)
    i_tomcat=$(_icono_svc tomcat)
    i_cert=$(_icono_cert)
    i_repo=$(_icono_repo)

    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║   PRACTICA 7 - DESPLIEGUE SEGURO E INSTALACION       ║"
    echo "  ║   HIBRIDA  (FTP/WEB)  +  SSL/TLS                     ║"
    echo "  ║   Sistema: Rocky Linux 9                              ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Estado actual:${NC}"
    echo -e "   $i_vsftpd vsftpd   $i_apache Apache   $i_nginx Nginx   $i_tomcat Tomcat"
    echo -e "   $i_cert Certificado SSL    $i_repo Repositorio FTP"
    echo ""
    echo -e "${CYAN}  ── REPOSITORIO FTP ─────────────────────────────────${NC}"
    echo "   1. Preparar repositorio FTP  (descargar binarios + sha256)"
    echo "   2. Ver estado del repositorio"
    echo ""
    echo -e "${CYAN}  ── INSTALACION DE SERVIDORES ───────────────────────${NC}"
    echo "   3. Instalar Apache HTTPD   (elige WEB o FTP + SSL opcional)"
    echo "   4. Instalar Nginx          (elige WEB o FTP + SSL opcional)"
    echo "   5. Instalar Tomcat         (elige WEB o FTP + SSL opcional)"
    echo ""
    echo -e "${CYAN}  ── SSL/TLS (aplicar a servicios ya instalados) ─────${NC}"
    echo "   6. Generar certificado SSL  (reprobados.com)"
    echo "   7. Activar SSL en Apache"
    echo "   8. Activar SSL en Nginx"
    echo "   9. Activar SSL en Tomcat"
    echo "  10. Activar FTPS en vsftpd"
    echo "  11. Verificacion completa SSL  (resumen de los 4 servicios)"
    echo ""
    echo -e "${CYAN}  ── UTILIDADES ───────────────────────────────────────${NC}"
    echo "  12. Ver estado de todos los servicios"
    echo "  13. Instalacion limpia completa  (servidor nuevo)"
    echo ""
    echo "   0. Salir"
    echo ""
    echo -e "${CYAN}  ────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}Nota: cada opcion valida sus dependencias automaticamente${NC}"
    echo ""
}

# =============================================================================
# INSTALACION LIMPIA COMPLETA (opcion 13)
# =============================================================================

instalacion_limpia() {
    echo ""
    warn "Esto instalara y configurara desde cero:"
    echo "  vsftpd + Repositorio FTP + Certificado SSL"
    echo "  Apache + Nginx + Tomcat (elige fuente para cada uno)"
    echo "  SSL/TLS en todos los servicios"
    echo ""
    read -rp "  Continuar? [s/N]: " confirm
    [[ "$confirm" =~ ^[sS]$ ]] || return

    # Prerequisitos del sistema
    info "Instalando prerequisitos del sistema..."
    dnf install -y curl wget openssl gcc make tar &>/dev/null
    ok "Prerequisitos listos"

    # Paso 1: vsftpd
    echo ""
    info "=== PASO 1/6: vsftpd ==="
    if systemctl is-active vsftpd &>/dev/null; then
        ok "vsftpd ya activo"
    else
        instalar_vsftpd
    fi

    # Paso 2: Repositorio FTP
    echo ""
    info "=== PASO 2/6: Repositorio FTP ==="
    preparar_repositorio_completo

    # Paso 3: Certificado SSL
    echo ""
    info "=== PASO 3/6: Certificado SSL ==="
    generar_certificado

    # Paso 4/5/6: Servidores HTTP
    for svc in apache nginx tomcat; do
        local num
        case "$svc" in apache) num=4;; nginx) num=5;; tomcat) num=6;; esac
        echo ""
        info "=== PASO $num/6: $(echo "$svc" | tr '[:lower:]' '[:upper:]') ==="
        instalar_servicio_completo "$svc"
    done

    # FTPS
    echo ""
    read -rp "  Activar FTPS en vsftpd? [S/n]: " r
    [[ "$r" =~ ^[nN]$ ]] || ssl_vsftpd

    # Resumen final
    echo ""
    resumen_ssl
    ver_estado_servicios

    ok "Instalacion limpia completada."
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

while true; do
    mostrar_menu
    read -rp "  Seleccione opcion (0-13): " opcion
    echo ""

    case "$opcion" in
        1)  preparar_repositorio_completo ;;
        2)  mostrar_estado_repo ;;
        3)  instalar_servicio_completo apache ;;
        4)  instalar_servicio_completo nginx  ;;
        5)  instalar_servicio_completo tomcat ;;
        6)  generar_certificado ;;
        7)
            _validar_cert || true
            read -rp "  Puerto HTTPS para Apache [443]: " ph
            ssl_apache 80 "${ph:-443}"
            ;;
        8)
            _validar_cert || true
            read -rp "  Puerto HTTPS para Nginx [443]: " ph
            ssl_nginx 80 "${ph:-443}"
            ;;
        9)
            _validar_cert || true
            read -rp "  Puerto HTTPS para Tomcat [8443]: " ph
            ssl_tomcat 8080 "${ph:-8443}"
            ;;
        10)
            _validar_cert || true
            ssl_vsftpd
            ;;
        11) resumen_ssl ;;
        12) ver_estado_servicios ;;
        13) instalacion_limpia ;;
        0)
            echo ""
            ok "Saliendo."
            exit 0
            ;;
        *)  warn "Opcion invalida: $opcion" ;;
    esac

    echo ""
    read -rp "  Presiona ENTER para continuar..." _
done