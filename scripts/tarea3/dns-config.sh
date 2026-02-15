#!/bin/bash

echo "---------------------------------------------------"
echo "-- Opciones                                      --"
echo "-- 1. Instalar Servidor                          --"
echo "-- 2. Configuracion                              --"
echo "-- 3. Lista de Concesiones y Estado del Servidor --"
echo "-- 4.Salir                                       --"
echo "---------------------------------------------------"

read -p "Seleccione una opcion: " op

case $op in
	1)
        if ! rpm -q bind > /dev/null 2>&1; then
            sudo dnf -y install -q bind  bind-utils > /dev/null 2>&1
            echo "[ OK ] bind se ha instalado correctamente."
        else
            echo "[ OK ] bind ya está instalado."
        fi
		;;
	4)
		exit 1 ;;
esac
