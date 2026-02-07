#!/bin/bash
. ~/cursobash/validadorIPv4.sh

#ver si tiene los paquetes necesarios

echo "----------------------------------"
echo "-- Verificacion de lo necesario --"
echo "----------------------------------"
#echo -e "\n"

if rpm -q kea > /dev/null 2>&1; then
	echo "[OK] El servidor ya esta instalado"
else
	echo "[INSTALANDO] Procediendo con la instalcion del servidor DHCP..."
	sudo dnf install kea -y
fi

read
clear

#Peticion de los datos necesarios
echo "----------------------------"
echo "-- Configuracion Dinamica --"
echo "----------------------------"

read -p "Nombre descriptivo: " scope
read -p "Rango inicial de direcciones IPv4: (ej. 192.168.100.50) " initIP
validarIP $initIP
if [ $res -ne 0 ]; then
	echo "Erro: La IP no cumpole con el formato de IPv4..."
	exit 1
fi

read -p "Rango final de direcciones IPv4: (ej. 192.168.100.150) " finIP
validarIP $finIP
if [ $res -ne 0 ]; then
	echo "Erro: La IP no cumpole con el formato de IPv4..."
	exit 1
fi

read -p "Tiempo de concesion en segundos: (ej. 3600) " timepo
read -p "Ingrese la IPv4 del Router/Gateway: " routerIP
validarIP $routerIP
if [ $res -ne 0 ]; then
	echo "Erro: La IP no cumpole con el formato de IPv4..."
	exit 1
fi

read -p "Ingrese la IPv4 del DNS: " dnsIP
validarIP $dnsIP
if [ $res -ne 0 ]; then
	echo "Erro: La IP no cumpole con el formato de IPv4..."
	exit 1
fi

if [ ! systemctl is-active kea-dhcp4 --quiet]; then
	echo "[!] Iniciando el servidor..."
	sudo systemctl start kea-dhcp4
	sudo systemctl enable kea dhcp4	
else
	echo "[OK] El servidor ya esta en ejecucion"
fi
	
read 

#echo "$(rpm -q kea)"

