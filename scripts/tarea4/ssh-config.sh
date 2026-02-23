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
        if rpm -q openssh-server > /dev/null 2>&1; then
            echo "[ ! ] SSH ya está instalado."
            exit 0
        fi
        sudo dnf install openssh-server -y > /dev/null 2>&1
        echo "SSH instalado correctamente."
        sudo systemctl enable sshd
        sudo systemctl start sshd

        sudo firewall-cmd --zone=public --add-service=ssh --permanent
        sudo firewall-cmd --reload
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