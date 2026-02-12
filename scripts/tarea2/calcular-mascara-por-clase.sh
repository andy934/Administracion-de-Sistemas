#!/bin/bash

calcular-mascara(){
    local ip=$1
    
    # Extraer primer octeto
    local primer_octeto=$(echo $ip | cut -d. -f1)
    
    if [ $primer_octeto -ge 1 ] && [ $primer_octeto -le 126 ]; then
        echo "8"
    elif [ $primer_octeto -ge 128 ] && [ $primer_octeto -le 191 ]; then
        echo "16"
    elif [ $primer_octeto -ge 192 ] && [ $primer_octeto -le 223 ]; then
        echo "24"
    else
        echo "24"
    fi
}