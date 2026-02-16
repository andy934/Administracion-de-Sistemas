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
    
    # Kea suele guardar las concesiones en un archivo .csv o .db
    # Usamos /var/lib/kea/kea-leases4.csv que es el estándar
    local archivo_leases="/var/lib/kea/kea-leases4.csv"

    if sudo [ -f "$archivo_leases" ]; then
        # Verificamos si el archivo tiene más que solo el encabezado
		local conteo=$(sudo wc -l < "$archivo_leases")
        if [ "$conteo" -gt 1 ]; then
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


#diagnosticoDHCP
