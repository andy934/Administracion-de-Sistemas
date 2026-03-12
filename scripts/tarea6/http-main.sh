#!/bin/bash
# =============================================================================
# http_main.sh — Script principal (solo llamadas a funciones)
# Práctica 6 — Despliegue Dinámico de Servicios HTTP Multi-Version
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/http_functions.sh"

# ─── Colores (heredados de functions) ────────────────────────────────────────
function mostrar_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║     DESPLIEGUE DINÁMICO DE SERVICIOS HTTP            ║"
    echo "  ║     Práctica 6 — Administración de Sistemas          ║"
    echo "  ║     Rocky Linux                                      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

function mostrar_menu() {
    mostrar_banner
    ver_estado_servicios
    echo -e "  ${YELLOW}── Instalación ─────────────────────────────────────${NC}"
    echo "   1. Instalar Apache httpd"
    echo "   2. Instalar Nginx"
    echo "   3. Instalar Apache Tomcat"
    echo ""
    echo -e "  ${YELLOW}── Administración ──────────────────────────────────${NC}"
    echo "   4. Ver estado de servicios"
    echo "   5. Cambiar puerto de un servicio"
    echo "   6. Ver logs de un servicio"
    echo "   7. Desinstalar un servicio"
    echo ""
    echo "   0. Salir"
    echo ""
}

function main() {
    # Verificar root/sudo
    if ! sudo -n true 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Este script requiere privilegios sudo."
        exit 1
    fi

    local opcion
    while true; do
        mostrar_menu
        read -p "  Seleccione una opción: " opcion

        case $opcion in
            1) instalar_apache ;;
            2) instalar_nginx ;;
            3) instalar_tomcat ;;
            4) ver_estado_servicios ;;
            5) cambiar_puerto_servicio ;;
            6) ver_logs_servicio ;;
            7) desinstalar_servicio ;;
            0) echo ""; echo "Saliendo..."; exit 0 ;;
            *) log_err "Opción inválida." ;;
        esac

        echo ""
        read -p "  Presione ENTER para continuar..." _
    done
}

main