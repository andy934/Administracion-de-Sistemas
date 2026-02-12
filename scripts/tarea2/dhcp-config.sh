#!/bin/bash
. ./validadorIPv4.sh
. ./diagnosticoDHCP.sh
. ./calcular-mascara-por-clase.sh

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
		if rpm -q kea > /dev/null 2>&1; then
			echo "[OK] El servidor ya esta instalado"
		else
			sudo dnf install kea -y
			echo "[INSTALANDO] Procediendo con la instalcion del servidor DHCP..."
		fi
		systemctl restart kea-dhcp4 ;;
	2)
		read -p "Nombre descriptivo: " scope
		
		read -p "Ingrese el segmento de red: " segmentoIP
		#validarIP $segmentoIP
		if ! validarIP "$segmentoIP" ; then
			echo "Error: La IP no cumpole con el formato de IPv4..."
			exit 1
		fi
		mascara=$(calcular-mascara $segmentoIP)
		cidr=$(echo $mascara | awk '{print $1}')

		read -p "Rango inicial de direcciones IPv4: (ej. 192.168.100.50) " initIP
		if ! validarIP "$initIP" ; then
			echo "Error: La IP no cumpole con el formato de IPv4..."
			exit 1
		fi
				
		read -p "Rango final de direcciones IPv4: (ej. 192.168.100.150) " finIP
		if ! validarIP "$finIP" ; then
			echo "Error: La IP no cumpole con el formato de IPv4..."
			exit 1
		fi

		#Validacion que las ips sean del segmento de red ingresado
		segmento_base=$(echo $segmentoIP | cut -d. -f1-3)
		init_base=$(echo $initIP | cut -d. -f1-3)
		fin_base=$(echo $finIP | cut -d. -f1-3)

		if [[ $init_base != $segmento_base* ]] || [[ $fin_base != $segmento_base* ]]; then
			echo "Error: Las IPs del rango no pertenecen al segmento $segmentoIP"
			exit 1
		fi
				
		read -p "Tiempo de concesion en segundos: (ej. 3600) " tiempo
		read -p "Ingrese la IPv4 del Router/Gateway: " routerIP
		if [[ -n "$routerIP" ]]; then
    		if ! validarIP "$routerIP"; then
        		echo "Error: Formato de Gateway no válido."
        		exit 1
    		fi
		fi

		read -p "Ingrese la IPv4 del DNS: " dnsIP
		if [[ -n "$dnsIP" ]]; then
    		if ! validarIP "$dnsIP"; then
        		echo "Error: Formato de DNS no válido."
        		exit 1
   			fi
		fi
				
		sudo -E tee /etc/kea/kea-dhcp4.conf <<EOF > /dev/null
{
"Dhcp4": {
	"interfaces-config": { 
		"interfaces": [ "ens192" ] 
	},
	"valid-lifetime": $tiempo,
	"subnet4": [ 
		{
			"id": 1,
			"subnet": "$segmentoIP/$mascara",
			"pools": [ { "pool": "$initIP - $finIP" } ],
			"option-data": [
				{ "name": "routers", "data": "$routerIP" },
				{ "name": "domain-name-servers", "data": "$dnsIP" }
			]
		} 
	]
}
}
EOF
						
		#Validacion del archivo .conf
		if sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf > /dev/null 2>&1; then
			echo "[OK] Archivo de configuracion sin errores. Aplicando cambios..."
			sudo systemctl restart kea-dhcp4
		else
			echo "[ERROR] El archivo de configuracion tiene errores. No se reinicio el servidor..."
			exit 1
		fi
		if ! systemctl is-active kea-dhcp4 --quiet; then
			sudo systemctl start kea-dhcp4
			sudo systemctl enable kea dhcp4	
		fi ;;

	3)
		diagnosticoDHCP ;;

	4)
		exit 1 ;;
esac

#ver si tiene los paquetes necesarios
#echo "----------------------------------"
#echo "-- Verificacion de lo necesario --"
#echo "----------------------------------"
#echo -e "\n"


#clear

#Peticion de los datos necesarios
#echo "----------------------------"
#echo "-- Configuracion Dinamica --"
#echo "----------------------------"
