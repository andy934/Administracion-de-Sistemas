#!/bin/bash

calcular-mascara(){
    local ip=$1
    local primer_octeto=$(echo $ip | cut -d. -f1)
    
    local cidr
    local mascara
    
    if [ $primer_octeto -ge 1 ] && [ $primer_octeto -le 126 ]; then
        cidr="8"
        mascara="255.0.0.0" # Clase A
    elif [ $primer_octeto -ge 128 ] && [ $primer_octeto -le 191 ]; then
        cidr="16"
        mascara="255.255.0.0" # Clase B
    elif [ $primer_octeto -ge 192 ] && [ $primer_octeto -le 223 ]; then
        cidr="24"
        mascara="255.255.255.0" # Clase C
    else
        cidr="24"
        mascara="255.255.255.0" # Default
    fi

    # Devolvemos ambos valores separados por un espacio para poder capturarlos
    echo "$cidr $mascara"
}