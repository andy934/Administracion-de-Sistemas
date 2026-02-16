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

		resultado=$(calcular-mascara "$segmentoIP")
		#Separamos los valores en variables individuales
		cidr=$(echo $resultado | awk '{print $1}')
		mascara=$(echo $resultado | awk '{print $2}')

		#Calculamos el IP del servidor dinámicamente segun la clase
        if [ "$cidr" -eq "8" ]; then
            segmento_base=$(echo $segmentoIP | cut -d. -f1)
            ip_servidor="${segmento_base}.0.0.1"
            red_formato="${segmento_base}.0.0.0"
        elif [ "$cidr" -eq "16" ]; then
            segmento_base=$(echo $segmentoIP | cut -d. -f1-2)
            ip_servidor="${segmento_base}.0.1"
            red_formato="${segmento_base}.0.0"
        else
            segmento_base=$(echo $segmentoIP | cut -d. -f1-3)
            ip_servidor="${segmento_base}.1"
            red_formateada="${segmento_base}.0"
        fi

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

		ultimo_octeto_srv=$(echo "$ip_servidor" | cut -d. -f4)
		ultimo_octeto_init=$(echo "$initIP" | cut -d. -f4)

		# Si son iguales, sumamos 1 automáticamente a la IP inicial
		if [ "$ultimo_octeto_srv" -eq "$ultimo_octeto_init" ]; then
			echo "Aviso: La IP inicial coincide con el servidor. Ajustando automáticamente a uno más..."
			
			# Reconstruimos la IP sumando 1 al último octeto
			prefijo_init=$(echo "$initIP" | cut -d. -f1-3)
			nuevo_octeto=$((ultimo_octeto_init + 1))
			initIP="${prefijo_init}.${nuevo_octeto}"
		fi

		sudo nmcli con mod "ens192" ipv4.addresses "${ip_servidor}/${cidr}" ipv4.method manual
        sudo nmcli con up "ens192"

		segmento_base=$(echo "$segmentoIP" | tr -d ' ' | cut -d. -f1-3)
		init_base=$(echo "$initIP" | tr -d ' ' | cut -d. -f1-3)
		fin_base=$(echo "$finIP" | tr -d ' ' | cut -d. -f1-3)

		# Comparamos las cadenas exactamente
		if [[ "$init_base" != "$segmento_base" ]] || [[ "$fin_base" != "$segmento_base" ]]; then
			echo "Error: Las IPs del rango no pertenecen al segmento $segmentoIP"
			exit 1
		fi

		read -p "Tiempo de concesion en segundos: (ej. 3600) " tiempo
		read -p "Ingrese la IPv4 del Router/Gateway: " routerIP
		

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
			"subnet": "$segmentoIP/$cidr",
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
