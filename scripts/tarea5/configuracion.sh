#!/bin/bash

# Función para verificar si vsftpd está instalado
function verificar_vsftpd() {
    if rpm -q vsftpd > /dev/null 2>&1; then
        return 0  # Instalado
    else
        return 1  # No instalado
    fi
}

# Función para instalar y configurar vsftpd
function instalar_vsftpd() {
    if verificar_vsftpd; then
        echo "[INFO] vsftpd ya está instalado."
        return 0
    fi
    
    echo "[INSTALANDO] vsftpd y dependencias..."
    sudo dnf install vsftpd openssl policycoreutils-python-utils -y > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "[OK] vsftpd instalado correctamente."
    else
        echo "[ERROR] No se pudo instalar vsftpd."
        return 1
    fi
}

# Función para crear estructura de directorios base
function crear_estructura_directorios() {
    echo "[INFO] Creando estructura de directorios FTP..."
    
    # Directorio base FTP
    sudo mkdir -p /srv/ftp/{general,reprobados,recursadores,usuarios}
    
    # Establecer permisos base
    sudo chmod 755 /srv/ftp
    sudo chmod 775 /srv/ftp/general
    sudo chmod 770 /srv/ftp/reprobados
    sudo chmod 770 /srv/ftp/recursadores
    sudo chmod 755 /srv/ftp/usuarios
    
    # Crear grupos si no existen
    if ! getent group reprobados > /dev/null 2>&1; then
        sudo groupadd reprobados
        echo "[OK] Grupo 'reprobados' creado."
    fi
    
    if ! getent group recursadores > /dev/null 2>&1; then
        sudo groupadd recursadores
        echo "[OK] Grupo 'recursadores' creado."
    fi
    
    # Asignar grupos a carpetas
    sudo chgrp reprobados /srv/ftp/reprobados
    sudo chgrp recursadores /srv/ftp/recursadores
    sudo chgrp ftp /srv/ftp/general
    
    echo "[OK] Estructura de directorios creada."
}

# Función para configurar vsftpd.conf
function configurar_vsftpd() {
    echo "[INFO] Configurando /etc/vsftpd/vsftpd.conf..."
    
    # Backup del archivo original
    if [ -f /etc/vsftpd/vsftpd.conf ]; then
        sudo cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Crear configuración
    sudo tee /etc/vsftpd/vsftpd.conf > /dev/null <<EOF
# Configuración básica
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES

# Acceso anónimo
anon_root=/srv/ftp/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Usuarios locales
local_root=/srv/ftp
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/srv/ftp

# Seguridad
seccomp_sandbox=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# Logs
xferlog_file=/var/log/vsftpd.log
vsftpd_log_file=/var/log/vsftpd.log

# SSL/TLS (opcional, deshabilitado por defecto)
ssl_enable=NO

# Lista de usuarios permitidos
userlist_enable=YES
userlist_file=/etc/vsftpd/user_list
userlist_deny=NO

# Mensaje de bienvenida
ftpd_banner=Bienvenido al servidor FTP - Administración de Sistemas
EOF
    
    # Crear archivo de usuarios permitidos si no existe
    if [ ! -f /etc/vsftpd/user_list ]; then
        sudo touch /etc/vsftpd/user_list
    fi
    
    echo "[OK] Archivo vsftpd.conf configurado."
}

# Función para configurar firewall
function configurar_firewall() {
    echo "[INFO] Configurando firewall para FTP..."
    
    sudo firewall-cmd --permanent --add-service=ftp > /dev/null 2>&1
    sudo firewall-cmd --permanent --add-port=40000-40100/tcp > /dev/null 2>&1
    sudo firewall-cmd --reload > /dev/null 2>&1
    
    echo "[OK] Firewall configurado."
}

# Función para configurar SELinux
function configurar_selinux() {
    if command -v getenforce > /dev/null 2>&1; then
        if [ "$(getenforce)" != "Disabled" ]; then
            echo "[INFO] Configurando SELinux para FTP..."
            
            sudo setsebool -P ftpd_full_access on
            sudo setsebool -P allow_ftpd_anon_write on
            sudo semanage fcontext -a -t public_content_rw_t "/srv/ftp(/.*)?"
            sudo restorecon -Rv /srv/ftp > /dev/null 2>&1
            
            echo "[OK] SELinux configurado."
        fi
    fi
}

# Función principal de instalación completa
function instalar_configurar_completo() {
    echo "=========================================="
    echo "INSTALACIÓN Y CONFIGURACIÓN COMPLETA FTP"
    echo "=========================================="
    echo ""
    
    # 1. Instalar vsftpd
    instalar_vsftpd
    if [ $? -ne 0 ]; then
        echo "[ERROR] No se pudo completar la instalación."
        return 1
    fi
    
    # 2. Crear estructura de directorios
    crear_estructura_directorios
    
    # 3. Configurar vsftpd
    configurar_vsftpd
    
    # 4. Configurar firewall
    configurar_firewall
    
    # 5. Configurar SELinux
    configurar_selinux
    
    # 6. Habilitar e iniciar servicio
    sudo systemctl enable vsftpd > /dev/null 2>&1
    sudo systemctl restart vsftpd
    
    if systemctl is-active vsftpd --quiet; then
        echo ""
        echo "=========================================="
        echo "[OK] Servidor FTP instalado y configurado"
        echo "=========================================="
        echo ""
        echo "Información del servicio:"
        echo "  • Estado: Activo"
        echo "  • Puerto: 21 (control), 40000-40100 (datos)"
        echo "  • Directorio base: /srv/ftp"
        echo "  • Acceso anónimo: Habilitado (solo lectura en /general)"
        echo ""
    else
        echo "[ERROR] El servicio vsftpd no está corriendo."
        sudo journalctl -xeu vsftpd.service --no-pager | tail -20
        return 1
    fi
}