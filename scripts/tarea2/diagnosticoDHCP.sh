#!/bin/bash

#funcion de diagnostico de servidor DHCP
#Verifica el estado del srv y el listado de cocesiones

diagnosticoDHCP(){
	echo "--------------------"
	echo "-- Monitoreo DHCP --"
	echo "--------------------"

	#verificaion del servidor
	echo -n "Estado del servidor: "
	systemctl is-active kea-dhcp4 --quiet && echo "ACTIVO" || echo "CAIDO"

	#listado de concesiones
	echo -e "\nEquipos conectados actualmente:"

    local archivo_leases="/var/lib/kea/kea-leases4.csv"

    if sudo test -f "$archivo_leases" ; then
        # Verificamos si el archivo tiene más que solo el encabezado
		local concesiones=$(sudo grep -c -v "^address,hwaddr" "$archivo_leases" 2>/dev/null)
        if [ "$concesiones" -gt 0 ]; then
            # Formateamos la salida: 
            # address, hwaddr, client_id, valid_lifetime, expire, subnet_id
            echo "IP_ADDRESS      MAC_ADDRESS         EXPIRACION"
            echo "----------------------------------------------------"
            sudo awk -F, 'NR>1 {print $1 "    " $2 "    " $5}' "$archivo_leases" | column -t
        else
            echo "No hay concesiones activas en la base de datos."
        fi
    else
        echo "Error: No se encontró el archivo de base de datos en $archivo_leases"
    fi
}


diagnosticoDHCP
