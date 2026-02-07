#!/bin/bash

#funcion validadora de IPv4

validarIP(){
	local uIP=$1

	regla='^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$'

	if [[ $uIP =~ $regla ]]; then
		res=0
	else
		res=1
	fi
}

#read -p "Ingrese una IP: " u_IP

#validarIP $u_IP

#echo $res
#echo $reaultado
