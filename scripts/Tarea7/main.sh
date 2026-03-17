#!/usr/bin/env bash
# =============================================================================
# main.sh - Orquestador principal Practica 7
# Infraestructura de Despliegue Seguro e Instalacion Hibrida (FTP/Web)
# Sistema: Rocky Linux 9
# =============================================================================

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Este script debe ejecutarse como root: sudo bash main.sh"
    exit 1
fi

# Ruta base de este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar modulos
source "$SCRIPT_DIR/func-repo.sh"
source "$SCRIPT_DIR/func-ssl.sh"
source "$SCRIPT_DIR/func-install.sh"

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

mostrar_menu() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║   PRACTICA 7 - DESPLIEGUE SEGURO                ║"
    echo "  ║   Instalacion Hibrida FTP/WEB + SSL/TLS         ║"
    echo "  ║   Rocky Linux 9                                 ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  ── REPOSITORIO FTP ───────────────────────────────"
    echo "   1. Preparar repositorio FTP (descargar binarios)"
    echo "   2. Ver estado del repositorio"
    echo ""
    echo "  ── INSTALACION DE SERVIDORES ─────────────────────"
    echo "   3. Instalar Apache HTTPD   (WEB o FTP)"
    echo "   4. Instalar Nginx          (WEB o FTP)"
    echo "   5. Instalar Tomcat         (WEB o FTP)"
    echo ""
    echo "  ── SSL/TLS ────────────────────────────────────────"
    echo "   6. Generar certificado SSL (reprobados.com)"
    echo "   7. Activar SSL en Apache"
    echo "   8. Activar SSL en Nginx"
    echo "   9. Activar SSL en Tomcat"
    echo "  10. Activar FTPS en vsftpd"
    echo "  11. Verificacion completa SSL (resumen)"
    echo ""
    echo "  ── UTILIDADES ─────────────────────────────────────"
    echo "  12. Ver estado de todos los servicios"
    echo "  13. Instalacion completa en servidor limpio"
    echo ""
    echo "   0. Salir"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
}

ver_estado_servicios() {
    echo ""
    echo -e "${CYAN}=== ESTADO DE SERVICIOS ===${NC}"
    echo ""
    local servicios=("vsftpd" "httpd-custom" "nginx-custom" "tomcat")
    for svc in "${servicios[@]}"; do
        local estado
        estado=$(systemctl is-active "$svc" 2>/dev/null)
        local color="${RED}"
        [ "$estado" = "active" ] && color="${GREEN}"
        printf "  %-20s %b%s%b\n" "$svc" "$color" "$estado" "$NC"
    done

    echo ""
    echo -e "${CYAN}=== PUERTOS EN ESCUCHA (HTTP/HTTPS/FTP) ===${NC}"
    ss -tlnp 2>/dev/null | grep -E ':21|:80|:443|:8080|:8443|:90[0-9]' | \
        awk '{print "  " $4}' | sort -u
    echo ""
}

instalacion_limpia() {
    echo ""
    warn "Esto instalara y configurara vsftpd + Apache + Nginx + Tomcat + SSL"
    read -rp "  Continuar? [s/N]: " confirm
    [[ "$confirm" =~ ^[sS]$ ]] || return

    verificar_prerequisitos

    # 1. vsftpd
    verificar_vsftpd

    # 2. Crear repo FTP
    crear_usuario_repo
    crear_estructura_repo
    poblar_repositorio

    # 3. Certificado SSL
    generar_certificado

    # 4. Instalar servidores (pregunta fuente para cada uno)
    for svc in apache nginx tomcat; do
        instalar_servicio_completo "$svc"
    done

    # 5. FTPS vsftpd
    echo ""
    read -rp "  Activar FTPS en vsftpd? [S/n]: " act_ftps
    [[ "$act_ftps" =~ ^[nN]$ ]] || ssl_vsftpd

    # 6. Resumen final
    resumen_ssl
    ver_estado_servicios

    ok "Instalacion completa finalizada."
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

while true; do
    mostrar_menu
    read -rp "  Seleccione opcion (0-13): " opcion

    case "$opcion" in
        1)
            crear_usuario_repo
            crear_estructura_repo
            poblar_repositorio
            ;;
        2)  mostrar_estado_repo ;;
        3)  instalar_servicio_completo apache ;;
        4)  instalar_servicio_completo nginx  ;;
        5)  instalar_servicio_completo tomcat ;;
        6)  generar_certificado ;;
        7)
            generar_certificado
            read -rp "  Puerto HTTPS para Apache (default 443): " ph
            ssl_apache 80 "${ph:-443}"
            ;;
        8)
            generar_certificado
            read -rp "  Puerto HTTPS para Nginx (default 443): " ph
            ssl_nginx 80 "${ph:-443}"
            ;;
        9)
            generar_certificado
            read -rp "  Puerto HTTPS para Tomcat (default 8443): " ph
            ssl_tomcat 8080 "${ph:-8443}"
            ;;
        10)
            generar_certificado
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
        *)  warn "Opcion invalida." ;;
    esac

    echo ""
    read -rp "  Presiona ENTER para continuar..." _
done