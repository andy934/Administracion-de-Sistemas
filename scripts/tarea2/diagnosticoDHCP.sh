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
	echo "Equipos conectados actualmente: "
	if [ -f /var/lib/kea-leases4.csv ]; then
		column -s, -t /var/lib/kea-leases4.csv | tail -n + 2
	else
		echo "No hay concesiones activas"
	fi
}
