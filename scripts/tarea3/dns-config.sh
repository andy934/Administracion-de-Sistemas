#!/bin/bash

echo "---------------------------------------------------"
echo "-- Opciones                                      --"
echo "-- 1. Instalar Servidor                          --"
echo "-- 2. Configuracion                              --"
echo "-- 3. Lista de Concesiones y Estado del Servidor --"
echo "-- 4.Salir                                       --"
echo "---------------------------------------------------"

read -p "\nSeleccione una opcion: " op

case $op in
	1)
        if ! rpm -q bind9 &> /dev/null; then
            sudo dnf install -y bind9
            echo "[ OK ] bind9 se ha instalado correctamente."
        else
            echo "[ OK ] bind9 ya está instalado."
        fi
		;;
	4)
		exit 1 ;;
esac
