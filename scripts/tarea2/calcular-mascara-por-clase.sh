#!/bin/bash

calcular-mascara(){
    local ip=$1
    
    # Extraer primer octeto
    local primer_octeto=$(echo $ip | cut -d. -f1)
    
    # Determinar clase y máscara
    if [ $primer_octeto -ge 1 ] && [ $primer_octeto -le 126 ]; then
        # Clase A
        echo "8"
    elif [ $primer_octeto -ge 128 ] && [ $primer_octeto -le 191 ]; then
        # Clase B
        echo "16"
    elif [ $primer_octeto -ge 192 ] && [ $primer_octeto -le 223 ]; then
        # Clase C
        echo "24"
    else
        # Clase D (multicast) o E (experimental)
        echo "24"
    fi
}