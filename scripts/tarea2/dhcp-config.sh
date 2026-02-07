#!/bin/bash
. ./validadorIPv4.sh
. ./diagnosticoDHCP.sh

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

read -p "Tiempo de concesion en segundos: (ej. 3600) " tiempo
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

#Archivo de configuracion

sudo bash -c "cat <<EOF > /etc/kea/kea-dhcp4.conf
{
\"Dhcp4\": {
	\"interfaces-config\": { \"interfaces\": [ \"ens192\" ] },
	\"valid-lifetime\": $tiempo,
	\"subnet4\": [ {
		\"subnet\": \"192.168.100.0/24\",
		\"pools\": [ { \"pool\": \"$initIP - $finIP\" } ],
		\"option-data\": [
			{ \"name\": \"routers\", \"data\": \"$routerIP\" },
			{ \"name\": \"domain-name-servers\", \"data\": \"$dnsIP\" }
		]
	} ]
}
}
EOF"

#Validacion del archivo .conf
if kea-dhcp4 -t /etc/kea/kea-dhcp4.conf > /dev/null 2>&1; then
	echo "[OK] Archivo de configuracion sin errores. Aplicando cambios..."
	sudo systemctl restart kea-dhcp4
else
	echo "[ERROR] El archivo de configuracion tiene errores. No se reinicio el servidor..."
	exit 1
fi

if [ ! systemctl is-active kea-dhcp4 --quiet ]; then
	sudo systemctl start kea-dhcp4
	sudo systemctl enable kea dhcp4	
fi

#diagnositico del servidor 
diagnosticoDHCP
	
read 

#echo "$(rpm -q kea)"

