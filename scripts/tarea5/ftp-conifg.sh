#!/bin/bash
. ./configuracion.sh
. ./alta-baja.sh

# Función para mostrar el menú
function mostrar_menu() {
    clear
    echo "=========================================================="
    echo "      AUTOMATIZACIÓN DE SERVIDOR FTP - VSFTPD"
    echo "=========================================================="
    echo "-- 1. Instalar y Configurar el servidor FTP           --"
    echo "-- 2. Ver estado del servicio vsftpd                  --"
    echo "-- 3. Alta de Usuario FTP                             --"
    echo "-- 4. Alta Masiva de Usuarios FTP                     --"
    echo "-- 5. Baja de Usuario FTP                             --"
    echo "-- 6. Cambio de grupo del Usuario FTP                 --"
    echo "-- 7. Lista de Usuarios FTP registrados               --"
    echo "-- 8. Ver permisos de un Usuario FTP                  --"
    echo "-- 9. Reiniciar el servicio vsftpd                    --"
    echo "-- 10. Ver logs del servicio                          --"
    echo "-- 11. Probar conexión FTP                            --"
    echo "-- 12. Reparar bind mounts (tras reinicio)            --"
    echo "-- 13. Salir                                          --"
    echo "=========================================================="
    echo ""
}

# Función para ver estado del servicio
function ver_estado_servicio() {
    echo ""
    echo "=== ESTADO DEL SERVICIO VSFTPD ==="
    echo ""

    if ! command -v vsftpd &> /dev/null; then
        echo "[ERROR] vsftpd no está instalado."
        return 1
    fi

    sudo systemctl status vsftpd --no-pager

    echo ""
    echo "Información adicional:"
    echo "  • Puerto de control: 21"
    echo "  • Puertos de datos: 40000-40100"
    echo "  • Archivo de configuración: /etc/vsftpd/vsftpd.conf"
    echo "  • Directorio base: /srv/ftp"
    echo ""
}

# Función para reiniciar servicio
function reiniciar_servicio() {
    echo ""
    echo "[INFO] Reiniciando servicio vsftpd..."

    sudo systemctl restart vsftpd

    if systemctl is-active vsftpd --quiet; then
        echo "[OK] Servicio reiniciado correctamente."
    else
        echo "[ERROR] El servicio no pudo iniciarse."
        sudo journalctl -xeu vsftpd.service --no-pager | tail -20
    fi
}

# Función para ver logs
function ver_logs() {
    echo ""
    echo "=== LOGS DEL SERVICIO VSFTPD ==="
    echo ""
    echo "Seleccione el tipo de log:"
    echo "  1. Logs del sistema (journalctl)"
    echo "  2. Logs de transferencias (/var/log/vsftpd.log)"
    echo "  3. Últimas 50 líneas de ambos"
    read -p "Opción (1-3): " log_opcion

    case $log_opcion in
        1)
            sudo journalctl -u vsftpd -n 50 --no-pager
            ;;
        2)
            if [ -f /var/log/vsftpd.log ]; then
                sudo tail -n 50 /var/log/vsftpd.log
            else
                echo "[INFO] No hay logs de transferencias aún."
            fi
            ;;
        3)
            echo "--- Logs del Sistema ---"
            sudo journalctl -u vsftpd -n 25 --no-pager
            echo ""
            echo "--- Logs de Transferencias ---"
            if [ -f /var/log/vsftpd.log ]; then
                sudo tail -n 25 /var/log/vsftpd.log
            else
                echo "[INFO] No hay logs de transferencias aún."
            fi
            ;;
        *)
            echo "[ERROR] Opción inválida."
            ;;
    esac
}

# Función para probar conexión FTP
function probar_conexion() {
    echo ""
    echo "=== PRUEBA DE CONEXIÓN FTP ==="
    echo ""

    if ! systemctl is-active vsftpd --quiet; then
        echo "[ERROR] El servicio vsftpd no está corriendo."
        return 1
    fi

    echo "Seleccione el tipo de conexión:"
    echo "  1. Anónimo (lectura en /general)"
    echo "  2. Usuario autenticado"
    read -p "Opción (1-2): " conexion_opcion

    ip_servidor=$(hostname -I | awk '{print $1}')

    case $conexion_opcion in
        1)
            echo ""
            echo "Datos de conexión anónima:"
            echo "  ftp $ip_servidor"
            echo "  Usuario:    anonymous"
            echo "  Contraseña: (enter vacío)"
            echo ""
            echo "FileZilla:"
            echo "  Host: ftp://$ip_servidor  Puerto: 21"
            echo "  Usuario: anonymous  Contraseña: (vacío)"
            ;;
        2)
            read -p "Nombre de usuario: " usuario_test
            echo ""
            echo "Datos de conexión:"
            echo "  ftp $ip_servidor"
            echo "  Usuario:    $usuario_test"
            echo "  Contraseña: (la configurada al crear el usuario)"
            echo ""
            echo "FileZilla:"
            echo "  Host: ftp://$ip_servidor  Puerto: 21"
            echo "  Usuario: $usuario_test"
            ;;
        *)
            echo "[ERROR] Opción inválida."
            ;;
    esac

    echo ""
    echo "Verificando puerto 21..."
    if sudo ss -tuln | grep -q ":21 "; then
        echo "[OK] El servidor está escuchando en el puerto 21."
    else
        echo "[ERROR] El servidor NO está escuchando en el puerto 21."
    fi
}

# Función principal
function main() {
    while true; do
        mostrar_menu
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)  instalar_configurar_completo ;;
            2)  ver_estado_servicio ;;
            3)  alta_usuario ;;
            4)  alta_masiva_usuarios ;;
            5)  baja_usuario ;;
            6)  cambiar_grupo_usuario ;;
            7)  listar_usuarios_ftp ;;
            8)  ver_permisos_usuario ;;
            9)  reiniciar_servicio ;;
            10) ver_logs ;;
            11) probar_conexion ;;
            12) reparar_mounts_usuarios ;;
            13)
                echo ""
                echo "Saliendo..."
                exit 0
                ;;
            *)
                echo ""
                echo "[ERROR] Opción no válida. Seleccione una opción del 1 al 13."
                ;;
        esac

        echo ""
        read -p "Presione ENTER para continuar..."
    done
}

# Verificar privilegios
if [ "$EUID" -ne 0 ]; then
    echo "[ADVERTENCIA] Este script requiere privilegios de superusuario."
    echo "Ejecute con: sudo bash ftp-config.sh"
    echo ""
fi

main