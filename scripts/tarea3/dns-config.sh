#!/bin/bash

echo "---------------------------------------------------"
echo "-- Opciones                                      --"
echo "-- 1. Instalar Servidor                          --"
echo "-- 2. Estado del Servidor                        --"
echo "-- 3. Configuracion                              --"
echo "-- 4. Lista de Concesiones y Estado del Servidor --"
echo "-- 5.Salir                                       --"
echo "---------------------------------------------------"

read -p "Seleccione una opcion: " op

case $op in
	1)
        if rpm -q bind > /dev/null 2>&1; then
            echo "[ OK ] bind ya está instalado."
        else
            sudo dnf -y install -q bind bind-utils > /dev/null 2>&1
            echo "[ OK ] bind se ha instalado correctamente."
        fi
		;;
    2)
        systemctl is-active named > /dev/null 2>&1 && 
        echo "[ OK ] El servidor DNS está activo." || echo "[ ERROR ] El servidor DNS no está activo."
        ;;
	4)
		exit 1 ;;
esac
