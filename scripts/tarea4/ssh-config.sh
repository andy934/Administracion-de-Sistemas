#!/bin/bash

echo "---------------------------------------------------"
echo "-- Opciones                                      --"
echo "-- 1. Instalar SSH                               --"
echo "-- 2. Status                                     --"
echo "-- 3. Salir                                      --"
echo "---------------------------------------------------"

read -p "Seleccione una opcion: " op

case $op in
    1)
        echo "Instalando SSH..."
        sudo dnf install openssh-server -y
        echo "SSH instalado correctamente."
        ;;
    2)
        echo "Verificando el estado del servicio SSH..."
        sudo systemctl status sshd
        ;;
    3)
        exit 0
        ;;
    *)
        echo "Opcion no valida. Por favor, seleccione una opcion del 1 al 3."
        ;;
esac