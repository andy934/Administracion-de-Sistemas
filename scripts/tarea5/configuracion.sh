#!/bin/bash

# Función para verificar si vsftpd está instalado
function verificar_vsftpd() {
    if rpm -q vsftpd > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Función para instalar vsftpd
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

    sudo mkdir -p /srv/ftp/{general,reprobados,recursadores,usuarios}

    # root:root 755 — vsftpd rechaza chroot si la raíz es escribible por el usuario
    sudo chown root:root /srv/ftp
    sudo chmod 755 /srv/ftp

    sudo chmod 777 /srv/ftp/general
    sudo chmod 770 /srv/ftp/reprobados
    sudo chmod 770 /srv/ftp/recursadores
    sudo chmod 755 /srv/ftp/usuarios

    if ! getent group reprobados > /dev/null 2>&1; then
        sudo groupadd reprobados
        echo "[OK] Grupo 'reprobados' creado."
    fi

    if ! getent group recursadores > /dev/null 2>&1; then
        sudo groupadd recursadores
        echo "[OK] Grupo 'recursadores' creado."
    fi

    sudo chgrp reprobados  /srv/ftp/reprobados
    sudo chgrp recursadores /srv/ftp/recursadores
    sudo chown root:ftp    /srv/ftp/general

    echo "[OK] Estructura de directorios creada."
}

# Función para configurar vsftpd.conf y PAM
function configurar_vsftpd() {
    echo "[INFO] Configurando /etc/vsftpd/vsftpd.conf..."

    if [ -f /etc/vsftpd/vsftpd.conf ]; then
        sudo cp /etc/vsftpd/vsftpd.conf \
            /etc/vsftpd/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi

    # FIX 1: anon_root=/srv/ftp/general — anonymous aterriza en /general
    #         y no puede ver carpetas de otros usuarios
    # FIX 2: local_root declarado UNA sola vez con user_sub_token=$USER
    #         (estaba duplicado, la 2ª línea pisaba la 1ª y rompía el sub_token)
    sudo tee /etc/vsftpd/vsftpd.conf > /dev/null <<'EOF'
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
# anonymous aterriza en /general y solo ve esa carpeta (sin acceso al resto)
anon_root=/srv/ftp/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Usuarios locales — cada usuario aterriza en /srv/ftp/$USER
user_sub_token=$USER
local_root=/srv/ftp/$USER
chroot_local_user=YES
allow_writeable_chroot=YES

# Seguridad
seccomp_sandbox=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# Logs
xferlog_file=/var/log/vsftpd.log
vsftpd_log_file=/var/log/vsftpd.log
log_ftp_protocol=YES
ssl_enable=NO

# Lista blanca de usuarios permitidos
# FIX 3: con userlist_deny=NO se necesita agregar "ftp" Y "anonymous"
#         vsftpd verifica el string literal "anonymous" antes de mapearlo
#         al usuario ftp del sistema — si no está en la lista, lo bloquea
userlist_enable=YES
userlist_file=/etc/vsftpd/user_list
userlist_deny=NO
pam_service_name=vsftpd

ftpd_banner=Bienvenido al servidor FTP - Administracion de Sistemas
EOF

    echo "[OK] vsftpd.conf configurado."

    # Inicializar user_list con las entradas base obligatorias
    sudo touch /etc/vsftpd/user_list
    for entrada in ftp anonymous; do
        if ! grep -q "^${entrada}$" /etc/vsftpd/user_list; then
            echo "$entrada" | sudo tee -a /etc/vsftpd/user_list > /dev/null
        fi
    done
    echo "[OK] user_list inicializado (ftp + anonymous)."

    # FIX 4: PAM de vsftpd necesita pam_unix.so para autenticar usuarios locales
    #         Solo pam_permit.so hace que vsftpd acepte el módulo pero rechace
    #         el login porque el ciclo de autenticación queda incompleto
    sudo tee /etc/pam.d/vsftpd > /dev/null <<'EOF'
#%PAM-1.0
auth       sufficient   pam_permit.so
auth       sufficient   pam_unix.so nullok
account    sufficient   pam_permit.so
account    sufficient   pam_unix.so
session    sufficient   pam_permit.so
EOF
    echo "[OK] /etc/pam.d/vsftpd configurado."
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
            sudo setsebool -P ftpd_full_access on 2>/dev/null
            sudo semanage fcontext -a -t public_content_rw_t "/srv/ftp(/.*)?" 2>/dev/null
            sudo restorecon -Rv /srv/ftp > /dev/null 2>&1
            echo "[OK] SELinux configurado."
        fi
    fi
}

# Función principal de instalación completa
function instalar_configurar_completo() {
    echo "=========================================="
    echo "INSTALACION Y CONFIGURACION COMPLETA FTP"
    echo "=========================================="
    echo ""

    instalar_vsftpd || return 1
    crear_estructura_directorios
    configurar_vsftpd
    configurar_firewall
    configurar_selinux

    sudo systemctl enable vsftpd > /dev/null 2>&1
    sudo systemctl restart vsftpd

    if systemctl is-active vsftpd --quiet; then
        echo ""
        echo "=========================================="
        echo "[OK] Servidor FTP instalado y configurado"
        echo "=========================================="
        echo ""
        echo "Informacion del servicio:"
        echo "  Puerto:           21 (control), 40000-40100 (datos)"
        echo "  Directorio base:  /srv/ftp"
        echo "  Acceso anonimo:   Habilitado (solo lectura en /general)"
        echo "  IP del servidor:  $(hostname -I | awk '{print $1}')"
        echo ""
    else
        echo "[ERROR] El servicio vsftpd no esta corriendo."
        sudo journalctl -xeu vsftpd.service --no-pager | tail -20
        return 1
    fi
}