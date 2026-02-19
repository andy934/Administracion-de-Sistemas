#!/bin/bash

echo "=========================================================="
echo "   AUTOMATIZACION DE SERVIDOR DNS - BIND"
echo "=========================================================="
echo "-- 1. Instalar Servidor DNS                            --"
echo "-- 2. Configurar Zona Directa (Forward Zone)           --"
echo "-- 3. Agregar Registro DNS                             --"
echo "-- 4. Eliminar Dominio                                 --"
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
        
        # Configurar named.conf para localhost
        echo "[INFO] Configurando named.conf..."
        sudo sed -i 's/listen-on port 53 { 127.0.0.1; };/#listen-on port 53 { 127.0.0.1; };/' /etc/named.conf
        sudo sed -i 's/listen-on-v6 port 53 { ::1; };/#listen-on-v6 port 53 { ::1; };/' /etc/named.conf
        
        # Verificar configuración
        if ! sudo named-checkconf 2>/dev/null; then
            echo "[ERROR] Hay errores en named.conf"
            sudo named-checkconf
            exit 1
        fi
        
        # Habilitar servicio
        sudo systemctl enable named > /dev/null 2>&1
        
        # Intentar iniciar
        sudo systemctl restart named
        
        # Verificar que esté corriendo
        sleep 2
        if systemctl is-active named --quiet; then
            echo "[OK] Servidor DNS iniciado correctamente"
        else
            echo "[ERROR] El servidor DNS no pudo iniciar"
            echo ""
            echo "Detalles del error:"
            sudo journalctl -xeu named.service --no-pager | tail -20
            exit 1
        fi
        
        # Configurar firewall
        sudo firewall-cmd --add-service=dns --permanent > /dev/null 2>&1
        sudo firewall-cmd --reload > /dev/null 2>&1
        
        echo "[OK] Firewall configurado"
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
        
    3)
        # Agregar registro DNS
        echo ""
        echo "=== AGREGAR REGISTRO DNS ==="
        echo ""
        
        read -p "Nombre del dominio existente: " dominio
        
        # Verificar que el archivo de zona exista
        if ! sudo test -f "/var/named/${dominio}.db"; then
            echo "[ERROR] No existe la zona ${dominio}"
            echo "Primero debe crear la zona con la opcion 2"
            exit 1
        fi
        
        echo ""
        echo "Tipos de registro disponibles:"
        echo "  A     - Nombre a IP (ej. www -> 192.168.1.10)"
        echo "  CNAME - Alias (ej. blog -> www)"
        echo ""
        read -p "Tipo de registro (A/CNAME): " tipo
        
        case $tipo in
            A|a)
                read -p "Nombre del host (ej. www, ftp, mail): " hostname
                read -p "Direccion IP: " ip
                
                echo "${hostname}    IN  A       ${ip}" | sudo tee -a /var/named/${dominio}.db > /dev/null
                echo "[OK] Registro A agregado: ${hostname}.${dominio} -> ${ip}"
                ;;
                
            CNAME|cname)
                read -p "Alias (ej. blog): " alias
                read -p "Nombre real (ej. www): " real
                
                echo "${alias}      IN  CNAME   ${real}.${dominio}." | sudo tee -a /var/named/${dominio}.db > /dev/null
                echo "[OK] Registro CNAME agregado: ${alias}.${dominio} -> ${real}.${dominio}"
                ;;
                
            *)
                echo "[ERROR] Tipo de registro no valido"
                exit 1
                ;;
        esac
        
        # Incrementar serial
        echo "[INFO] Recuerda incrementar el serial en el archivo de zona para que los cambios se propaguen"
        
        # Verificar y reiniciar
        if sudo named-checkzone ${dominio} /var/named/${dominio}.db > /dev/null 2>&1; then
            echo "[OK] Archivo de zona correcto"
            sudo systemctl reload named
            echo "[OK] Configuracion recargada"
        else
            echo "[ERROR] Hay errores en el archivo de zona"
            sudo named-checkzone ${dominio} /var/named/${dominio}.db
        fi
        ;;
        
    4)
        # Eliminar dominio
        echo ""
        echo "=== ELIMINAR DOMINIO ==="
        echo ""
        
        # Listar dominios configurados
        echo "Dominios configurados:"
        sudo grep -E "^zone" /etc/named.conf | grep -v "^\s*//" | awk '{print "  - " $2}' | tr -d '"'
        echo ""
        
        read -p "Nombre del dominio a eliminar: " dominio
        
        # Confirmar
        read -p "¿Estas seguro de eliminar ${dominio}? (s/n): " confirmar
        
        if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
            echo "[INFO] Operacion cancelada"
            exit 0
        fi
        
        # Eliminar zona de named.conf
        if sudo grep -q "zone \"${dominio}\"" /etc/named.conf; then
            echo "[INFO] Eliminando zona de named.conf..."
            # Crear backup
            sudo cp /etc/named.conf /etc/named.conf.backup.$(date +%Y%m%d_%H%M%S)
            
            # Eliminar la zona (desde // Forward Zone hasta };)
            sudo sed -i "/\/\/ Forward Zone for ${dominio}/,/^};/d" /etc/named.conf
            
            echo "[OK] Zona eliminada de named.conf"
        else
            echo "[ADVERTENCIA] La zona ${dominio} no existe en named.conf"
        fi
        
        # Eliminar archivo de zona
        if sudo test -f "/var/named/${dominio}.db"; then
            sudo rm -f /var/named/${dominio}.db
            echo "[OK] Archivo de zona eliminado: /var/named/${dominio}.db"
        else
            echo "[ADVERTENCIA] No existe el archivo /var/named/${dominio}.db"
        fi
        
        # Verificar configuración
        if sudo named-checkconf 2>/dev/null; then
            echo "[OK] Configuracion correcta"
            sudo systemctl restart named
            echo "[OK] Servidor DNS reiniciado"
        else
            echo "[ERROR] Hay errores en named.conf"
            echo "[INFO] Restaurando backup..."
            sudo cp /etc/named.conf.backup.$(date +%Y%m%d)* /etc/named.conf
            exit 1
        fi
        
        echo ""
        echo "[OK] Dominio ${dominio} eliminado correctamente"
        ;;
        
    5)
        # Verificar configuracion
        echo ""
        echo "=== VERIFICACION DE CONFIGURACION ==="
        echo ""
        
        echo -n "Verificando /etc/named.conf... "
        if sudo named-checkconf 2>/dev/null; then
            echo "[OK]"
        else
            echo "[ERROR]"
            sudo named-checkconf
        fi
        
        echo ""
        echo "Zonas configuradas:"
        sudo grep -E "^zone" /etc/named.conf | grep -v "^\s*//"
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