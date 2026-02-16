#!/bin/bash

echo "=========================================================="
echo "   AUTOMATIZACION DE SERVIDOR DNS - BIND"
echo "=========================================================="
echo "-- 1. Instalar Servidor DNS                            --"
echo "-- 2. Configurar Zona Directa (Forward Zone)           --"
echo "-- 3. Configurar Zona Inversa (Reverse Zone)           --"
echo "-- 4. Agregar Registro DNS                             --"
echo "-- 5. Verificar Configuracion                          --"
echo "-- 6. Ver Estado del Servidor                          --"
echo "-- 7. Salir                                            --"
echo "=========================================================="
read -p "Seleccione una opcion: " op

case $op in
	1)
        # Instalar BIND
        if rpm -q bind > /dev/null 2>&1; then
            echo "[OK] BIND ya esta instalado"
        else
            echo "[INSTALANDO] Servidor DNS BIND..."
            sudo dnf -y install bind bind-utils > /dev/null 2>&1
            echo "[OK] BIND instalado correctamente"
        fi
        
        # Habilitar e iniciar servicio
        sudo systemctl enable named > /dev/null 2>&1
        sudo systemctl start named
        
        # Configurar firewall
        sudo firewall-cmd --add-service=dns --permanent > /dev/null 2>&1
        sudo firewall-cmd --reload > /dev/null 2>&1
        
        echo "[OK] Servidor DNS iniciado y firewall configurado"
        ;;
        
    2)
          # Configurar Zona Directa
        echo ""
        echo "=== CONFIGURACION DE ZONA DIRECTA ==="
        echo ""
        
        read -p "Nombre del dominio (ej. reprobados.lan): " dominio
        read -p "IP del servidor DNS primario: " ip_dns
        read -p "Email del administrador (ej. admin): " email_admin
        
        # Generar serial (formato: YYYYMMDDNN)
        serial=$(date +%Y%m%d)01
        
        echo "[INFO] Generando archivo de zona directa..."
        
        # CREAR archivo de zona directa usando plantilla cat <<EOF
        sudo tee /var/named/${dominio}.db > /dev/null <<EOF
\$TTL 86400
@   IN  SOA dns-primary.${dominio}. ${email_admin}.${dominio}. (
            ${serial}      ; Serial
            3600           ; Refresh
            1800           ; Retry
            604800         ; Expire
            86400 )        ; Minimum TTL

; Name Server Information
@       IN  NS      dns-primary.${dominio}.

; IP for Name Server
dns-primary IN  A       ${ip_dns}

; A Records for hosts
@       IN  A       ${ip_dns}
EOF
        
        # Establecer permisos correctos
        sudo chown named:named /var/named/${dominio}.db
        sudo chmod 640 /var/named/${dominio}.db
        
        echo "[OK] Archivo de zona creado: /var/named/${dominio}.db"
        
        # AGREGAR zona a /etc/named.conf
        echo "[INFO] Agregando zona a /etc/named.conf..."
        
        # Verificar si la zona ya existe
        if sudo grep -q "zone \"${dominio}\"" /etc/named.conf; then
            echo "[ADVERTENCIA] La zona ${dominio} ya existe en named.conf"
        else
            # Agregar zona al final del archivo
            sudo tee -a /etc/named.conf > /dev/null <<EOF

// Forward Zone for ${dominio}
zone "${dominio}" IN {
    type master;
    file "${dominio}.db";
    allow-update { none; };
    allow-query { any; };
};
EOF
            echo "[OK] Zona agregada a /etc/named.conf"
        fi
        
        # Verificar configuracion
        echo "[INFO] Verificando configuracion..."
        if sudo named-checkconf; then
            echo "[OK] Configuracion de named.conf correcta"
        else
            echo "[ERROR] Hay errores en named.conf"
            exit 1
        fi
        
        if sudo named-checkzone ${dominio} /var/named/${dominio}.db > /dev/null 2>&1; then
            echo "[OK] Archivo de zona ${dominio}.db correcto"
        else
            echo "[ERROR] Hay errores en el archivo de zona"
            sudo named-checkzone ${dominio} /var/named/${dominio}.db
            exit 1
        fi
        
        # Reiniciar servicio
        sudo systemctl restart named
        echo "[OK] Servidor DNS reiniciado"
        echo ""
        echo "=========================================="
        echo "ZONA DIRECTA CONFIGURADA:"
        echo "=========================================="
        echo "Dominio: ${dominio}"
        echo "Servidor DNS: dns-primary.${dominio}"
        echo "IP: ${ip_dns}"
        echo "Archivo de zona: /var/named/${dominio}.db"
        echo "=========================================="
        ;;
    6)
        # Ver estado del servidor
        echo ""
        echo "=== ESTADO DEL SERVIDOR DNS ==="
        echo ""
        sudo systemctl status named --no-pager
        ;;
        
    7)
        exit 0
        ;;
        
    *)
        echo "[ERROR] Opcion no valida"
        exit 1
        ;;
esac
