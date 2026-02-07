#!/bin/bash

#ver si tiene los paquetes necesarios

echo "----------------------------------"
echo "-- Verificacion de lo necesario --"
echo "----------------------------------"
#echo -e "\n"

if rpm -q kea > /dev/null 2>&1; then
	echo "[OK] El servidor ya esta instalado"
else
	read -p "Requiere de la instalacion del servidor DHCP, continuar (s/n): " op

	if [ "$op" == 's' ]; then
		echo "[INSTALANDO] Procediendo con la instalcion del servidor DHCP..."
		sudo dnf install kea -y
	fi
fi

read
clear

#Peticion de los datos necesarios
echo "----------------------------"
echo "-- Configuracion Dinamica --"
echo "----------------------------"

read -p "Nombre descriptivo: " scope
read -p "Rango inicial de direcciones IPv4: (ej. 192.168.100.50) " initIP
read -p "Rango final de direcciones IPv4: (ej. 192.168.100.150) " finIP
read -p "Tiempo de concesion en segundos: (ej. 3600) " timepo
read -p "Ingrese la IPv4 del Router/Gateway: " routerIP
read -p "Ingrese la IPv4 del DNS: " dnsIP

if [ ! systemctl is-active kea-dhcp4 --quiet]; then
	read -p "El servidor esta apagado, iniciar (s/n): " op

	if [ "$op" == 's' ]; then
		echo "[!] Iniciando el servidor..."
		sudo systemctl start kea-dhcp4
		sudo systemctl enable kea dhcp4	
	fi
else
	echo "[OK] El servidor ya esta en ejecucion"
fi
	
read 

#echo "$(rpm -q kea)"

