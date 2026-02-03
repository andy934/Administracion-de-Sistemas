#!/bin/bash

echo "	------------------------"
echo "	--ESSTADO DEL SERVIDOR--"
echo "	------------------------"

echo "Nombre del Host: $(hostname)"

echo "IP actual: $(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)"

echo "El espacio en el SO es de: $(df -h / | awk 'NR==2 {print $4}')"
