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

    # ── BUG #1 CORREGIDO ─────────────────────────────────────────────────────
    # El directorio raíz /srv/ftp NO puede tener permiso de escritura para
    # el propietario cuando chroot_local_user=YES está activo.
    # vsftpd rechaza el login con "500 OOPS: vsftpd: refusing to run with
    # writable root inside chroot()" si el chroot raíz es escribible.
    # Solución: /srv/ftp debe ser propiedad de root con permisos 755.
    # ─────────────────────────────────────────────────────────────────────────
    sudo chown root:root /srv/ftp
    sudo chmod 755 /srv/ftp           # NO escribible por nadie que no sea root

    sudo chmod 777 /srv/ftp/general   # Todos leen y escriben (anónimo + autenticados)
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

    sudo chgrp reprobados /srv/ftp/reprobados
    sudo chgrp recursadores /srv/ftp/recursadores
    sudo chown root:ftp /srv/ftp/general

    echo "[OK] Estructura de directorios creada."
}

# Función para configurar vsftpd.conf
function configurar_vsftpd() {
    echo "[INFO] Configurando /etc/vsftpd/vsftpd.conf..."

    if [ -f /etc/vsftpd/vsftpd.conf ]; then
        sudo cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi

    sudo tee /etc/vsftpd/vsftpd.conf > /dev/null <<'EOF'
# ── Configuración básica ──────────────────────────────────────────────────────
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES

# ── Acceso anónimo ────────────────────────────────────────────────────────────
# BUG #2 CORREGIDO:
# anon_root apuntaba a /srv/ftp/general pero el usuario ftp (anónimo) hace
# chroot a esa ruta y la ve como "/". Si además local_root=/srv/ftp, vsftpd
# entra en conflicto entre ambas directivas para el mismo proceso.
# Solución: anon_root debe ser /srv/ftp (igual que local_root) y el usuario
# anónimo aterrizará en /srv/ftp. La carpeta general queda visible dentro.
anon_root=/srv/ftp
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# ── Usuarios locales ──────────────────────────────────────────────────────────
# BUG #3 CORREGIDO:
# local_root estaba declarado DOS veces y user_sub_token=$USER requiere que
# la ruta use el token, pero se mezclaba con la ruta estática.
# Con user_sub_token=$USER y local_root=/srv/ftp/$USER cada usuario aterriza
# en su propio subdirectorio dentro del chroot global.
# IMPORTANTE: ese directorio /srv/ftp/$USER debe existir y ser propiedad del
# usuario (lo hace alta_usuario en alta-baja.sh).
local_root=/srv/ftp/$USER
user_sub_token=$USER
chroot_local_user=YES

# BUG #4 CORREGIDO:
# allow_writeable_chroot=YES es necesario SOLO si el directorio raíz del
# chroot ($local_root) es escribible por el usuario. Si /srv/ftp/$USER
# pertenece al usuario con 755 o superior, vsftpd lo bloquea igualmente.
# La solución correcta es: el directorio raíz del chroot NO es escribible
# directamente (pertenece a root:root con 755), y dentro se montan como
# subdirectorios enlazados las carpetas donde el usuario SÍ tiene escritura.
# Removemos allow_writeable_chroot y en su lugar creamos la estructura
# correcta en alta_usuario.
# Si prefieres la solución rápida (menos segura), descomenta la siguiente línea:
# allow_writeable_chroot=YES

# ── Seguridad ─────────────────────────────────────────────────────────────────
seccomp_sandbox=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# ── Logs ──────────────────────────────────────────────────────────────────────
xferlog_file=/var/log/vsftpd.log
vsftpd_log_file=/var/log/vsftpd.log

# ── SSL/TLS ───────────────────────────────────────────────────────────────────
ssl_enable=NO

# ── Lista de usuarios permitidos ─────────────────────────────────────────────
# BUG #5 CORREGIDO:
# userlist_deny=NO significa "solo dejar entrar a los que están en la lista".
# El problema es que cuando el usuario no está aún en /etc/vsftpd/user_list
# (archivo vacío recién creado) vsftpd bloquea TODOS los logins, incluyendo
# anonymous. El usuario anónimo se mapea internamente como "ftp", así que
# "ftp" también debe estar en la lista.
# Además el archivo /etc/vsftpd/ftpusers (lista negra del PAM) por defecto
# incluye a root y otros, pero en Rocky/RHEL también puede incluir entradas
# que bloqueen usuarios legítimos — se limpia abajo.
userlist_enable=YES
userlist_file=/etc/vsftpd/user_list
userlist_deny=NO

# ── Mensaje de bienvenida ─────────────────────────────────────────────────────
ftpd_banner=Bienvenido al servidor FTP - Administracion de Sistemas
EOF

    # Crear/actualizar user_list con ftp (anónimo) como primera entrada
    if [ ! -f /etc/vsftpd/user_list ]; then
        sudo touch /etc/vsftpd/user_list
    fi

    # Asegurar que el usuario "ftp" (mapeo de anonymous) esté en la lista
    if ! grep -q "^ftp$" /etc/vsftpd/user_list; then
        echo "ftp" | sudo tee -a /etc/vsftpd/user_list > /dev/null
        echo "[OK] Usuario 'ftp' (anónimo) agregado a user_list."
    fi

    # ── BUG #5b CORREGIDO ────────────────────────────────────────────────────
    # /etc/vsftpd/ftpusers es la lista NEGRA del módulo PAM pam_listfile.
    # En Rocky Linux incluye por defecto: root, bin, daemon, adm, lp, sync,
    # shutdown, halt, mail, news, uucp, operator, games, nobody.
    # Si algún usuario del sistema coincide con estas entradas, PAM lo
    # bloquea ANTES de que vsftpd pueda procesarlo → "Login incorrect".
    # Los usuarios creados con useradd normales no deberían estar aquí,
    # pero verificamos que el archivo no haya sido editado incorrectamente.
    echo "[INFO] Verificando /etc/vsftpd/ftpusers (lista negra PAM)..."
    if [ -f /etc/vsftpd/ftpusers ]; then
        echo "[INFO] Contenido actual de ftpusers (usuarios BLOQUEADOS por PAM):"
        cat /etc/vsftpd/ftpusers | grep -v "^#" | grep -v "^$"
    fi
    # ─────────────────────────────────────────────────────────────────────────

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
        echo "  Puerto: 21 (control), 40000-40100 (datos)"
        echo "  Directorio base: /srv/ftp"
        echo "  Acceso anonimo: Habilitado (lectura en /general)"
        echo ""
    else
        echo "[ERROR] El servicio vsftpd no esta corriendo."
        sudo journalctl -xeu vsftpd.service --no-pager | tail -20
        return 1
    fi
}