#!/bin/bash
. ./configuracion.sh
. ./alta-baja.sh

echo "	------------------------"
echo "	-- CONFIGURACIÓN FTP  --"
echo "	------------------------"
echo ""
echo "1. Instalar y Configurar el servidor FTP (vsftpd)"
echo "2. Ver estado del servicio vsftpd"
echo "3. Alta de Usuario FTP"
echo "4. Baja de Usuario FTP"
echo "5. Cambio de grupo del Usuario FTP"
echo "6. Lista de Usuarios FTP registrados"
echo "7. Ver permisos de un Usuario FTP"
echo "8. Reiniciar el servicio vsftpd"
echo "9. Salir"
echo ""
read -p "Seleccione una opción: " opcion

case $opcion in
    1)
        sudo dnf install vsftpd openssl -y
        sudo systemctl enable vsftpd
        ;;
    2)
        
        ;;
    *)
        echo "Opción no válida. Por favor, seleccione una opción del 1 al 9."
        ;;
esac