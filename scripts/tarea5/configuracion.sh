#!/bin/bash

function configurar_vsftpd() {
    echo "Instalando vsftpd..."
    sudo apt update
    sudo apt install vsftpd -y
    echo "vsftpd instalado correctamente."
}