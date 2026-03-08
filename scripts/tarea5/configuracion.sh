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

    # general: todos los usuarios autenticados pueden leer y escribir
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

    # ── Directorio para usuario anónimo ──────────────────────────────────────
    # vsftpd con chroot_local_user=YES ignora anon_root; el usuario "ftp" del
    # sistema aterriza en su home directory. Lo apuntamos a /srv/ftp/anonymous
    # con solo /general adentro (solo lectura para anonymous).
    echo "[INFO] Configurando directorio para acceso anónimo..."
    sudo mkdir -p /srv/ftp/anonymous/general
    sudo chown root:root /srv/ftp/anonymous
    sudo chmod 755 /srv/ftp/anonymous          # raíz del chroot: NO escribible
    sudo chown root:root /srv/ftp/anonymous/general
    sudo chmod 755 /srv/ftp/anonymous/general  # mount point: NO escribible

    # Montar /srv/ftp/general dentro del chroot anonymous
    if ! mountpoint -q /srv/ftp/anonymous/general 2>/dev/null; then
        sudo mount --bind /srv/ftp/general /srv/ftp/anonymous/general
    fi
    if ! grep -q "anonymous/general" /etc/fstab; then
        echo "/srv/ftp/general  /srv/ftp/anonymous/general  none  bind  0 0" \
            | sudo tee -a /etc/fstab > /dev/null
    fi

    # Cambiar home del usuario ftp del sistema a /srv/ftp/anonymous
    sudo usermod -d /srv/ftp/anonymous ftp 2>/dev/null

    echo "[OK] Estructura de directorios creada."
}

# Función para reparar bind mounts de todos los usuarios existentes
# (útil tras reinicio del servidor o si se crearon usuarios manualmente)
function reparar_mounts_usuarios() {
    echo "[INFO] Verificando y reparando bind mounts de usuarios FTP..."

    local reparados=0

    # Obtener todos los usuarios de ambos grupos
    for usuario in $(getent group reprobados recursadores | cut -d: -f4 | tr ',' '\n' | sort -u); do
        [ -z "$usuario" ] && continue
        ! id "$usuario" &>/dev/null && continue

        grupo=$(id -gn "$usuario" 2>/dev/null)
        [[ "$grupo" != "reprobados" && "$grupo" != "recursadores" ]] && continue

        # Verificar y montar /general
        sudo mkdir -p /srv/ftp/$usuario/general
        if ! mountpoint -q /srv/ftp/$usuario/general 2>/dev/null; then
            sudo mount --bind /srv/ftp/general /srv/ftp/$usuario/general
            echo "  [MOUNT] $usuario/general"
            ((reparados++))
        fi
        if ! grep -q "/srv/ftp/$usuario/general" /etc/fstab; then
            echo "/srv/ftp/general  /srv/ftp/$usuario/general  none  bind  0 0" \
                | sudo tee -a /etc/fstab > /dev/null
        fi

        # Verificar y montar carpeta de grupo
        sudo mkdir -p /srv/ftp/$usuario/$grupo
        if ! mountpoint -q /srv/ftp/$usuario/$grupo 2>/dev/null; then
            sudo mount --bind /srv/ftp/$grupo /srv/ftp/$usuario/$grupo
            echo "  [MOUNT] $usuario/$grupo"
            ((reparados++))
        fi
        if ! grep -q "/srv/ftp/$usuario/$grupo" /etc/fstab; then
            echo "/srv/ftp/$grupo  /srv/ftp/$usuario/$grupo  none  bind  0 0" \
                | sudo tee -a /etc/fstab > /dev/null
        fi
    done

    # Verificar anonymous — usa anon-general (755) no general (777)
    if ! mountpoint -q /srv/ftp/anonymous/general 2>/dev/null; then
        sudo mount --bind /srv/ftp/anon-general /srv/ftp/anonymous/general
        echo "  [MOUNT] anonymous/general"
        ((reparados++))
    fi

    sudo systemctl daemon-reload

    if [ $reparados -eq 0 ]; then
        echo "[OK] Todos los bind mounts están activos. No se requirió reparación."
    else
        echo "[OK] Se repararon $reparados bind mount(s)."
    fi
}

# Función para configurar vsftpd.conf y PAM
function configurar_vsftpd() {
    echo "[INFO] Configurando /etc/vsftpd/vsftpd.conf..."

    if [ -f /etc/vsftpd/vsftpd.conf ]; then
        sudo cp /etc/vsftpd/vsftpd.conf \
            /etc/vsftpd/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi

    # FIX 1: anon_root es ignorado cuando chroot_local_user=YES está activo.
    #         vsftpd usa el home del usuario "ftp" del sistema como raíz.
    #         La solución: user_config_dir con chroot_local_user=NO solo para ftp.
    # FIX 2: local_root declarado UNA sola vez con user_sub_token=$USER
    # FIX 5: anonymous/general con 777 causa "writable root inside chroot"
    #         Se usa /srv/ftp/anon-general (755) como origen del bind mount.
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
# anon_root es ignorado con chroot_local_user=YES
# El usuario ftp aterriza en su home (/srv/ftp/anonymous) via user_config_dir
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Usuarios locales — cada usuario aterriza en /srv/ftp/$USER
user_sub_token=$USER
local_root=/srv/ftp/$USER
chroot_local_user=YES
allow_writeable_chroot=YES

# Configuración por usuario (excluye a ftp/anonymous del chroot)
user_config_dir=/etc/vsftpd/users

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

    # Crear user_config_dir y config especifica para ftp (anonymous)
    # El usuario ftp NO debe tener chroot para que aterrice en /srv/ftp/anonymous
    # con solo /general adentro (755, no escribible)
    sudo mkdir -p /etc/vsftpd/users
    sudo tee /etc/vsftpd/users/ftp > /dev/null <<'EOF'
local_root=/srv/ftp/anonymous
chroot_local_user=NO
EOF
    echo "[OK] user_config_dir configurado (ftp sin chroot)."

    # Crear /srv/ftp/anon-general como origen 755 para el bind mount de anonymous
    # No se puede usar /srv/ftp/general (777) porque vsftpd rechaza directorios
    # escribibles dentro del chroot de anonymous
    sudo mkdir -p /srv/ftp/anon-general
    sudo chmod 755 /srv/ftp/anon-general
    sudo chown root:root /srv/ftp/anon-general
    # Sincronizar contexto SELinux
    sudo semanage fcontext -a -t public_content_t "/srv/ftp/anon-general(/.*)?" 2>/dev/null
    sudo restorecon -Rv /srv/ftp/anon-general > /dev/null 2>&1

    # Actualizar bind mount de anonymous para usar anon-general en lugar de general
    sudo umount /srv/ftp/anonymous/general 2>/dev/null
    sudo sed -i '\|/srv/ftp/general.*anonymous/general|d' /etc/fstab
    sudo sed -i '\|/srv/ftp/anon-general.*anonymous/general|d' /etc/fstab
    sudo mount --bind /srv/ftp/anon-general /srv/ftp/anonymous/general
    echo "/srv/ftp/anon-general  /srv/ftp/anonymous/general  none  bind  0 0" \
        | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
    echo "[OK] Bind mount de anonymous apunta a anon-general (755)."

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
    reparar_mounts_usuarios

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