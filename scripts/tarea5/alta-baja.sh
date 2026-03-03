#!/bin/bash

# Función para validar nombre de usuario
function validar_usuario() {
    local usuario=$1

    if [ -z "$usuario" ]; then
        echo "[ERROR] El nombre de usuario no puede estar vacío."
        return 1
    fi

    if [[ ! "$usuario" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
        echo "[ERROR] Nombre de usuario inválido."
        echo "Debe: comenzar con letra minúscula, 3-16 caracteres, solo letras, números, guión y guión bajo."
        return 1
    fi

    return 0
}

# Función para validar grupo
function validar_grupo() {
    local grupo=$1
    if [ "$grupo" != "reprobados" ] && [ "$grupo" != "recursadores" ]; then
        echo "[ERROR] Grupo inválido. Debe ser 'reprobados' o 'recursadores'."
        return 1
    fi
    return 0
}

# Función para dar de alta un usuario FTP
function alta_usuario() {
    echo ""
    echo "=== ALTA DE USUARIO FTP ==="
    echo ""

    read -p "Nombre de usuario: " usuario
    if ! validar_usuario "$usuario"; then
        return 1
    fi

    if id "$usuario" &>/dev/null; then
        echo "[ERROR] El usuario '$usuario' ya existe en el sistema."
        return 1
    fi

    read -sp "Contraseña: " password
    echo ""
    read -sp "Confirmar contraseña: " password2
    echo ""

    if [ "$password" != "$password2" ]; then
        echo "[ERROR] Las contraseñas no coinciden."
        return 1
    fi

    if [ ${#password} -lt 6 ]; then
        echo "[ERROR] La contraseña debe tener al menos 6 caracteres."
        return 1
    fi

    echo ""
    echo "Seleccione el grupo:"
    echo "  1. reprobados"
    echo "  2. recursadores"
    read -p "Opción (1 o 2): " grupo_opcion

    case $grupo_opcion in
        1) grupo="reprobados" ;;
        2) grupo="recursadores" ;;
        *)
            echo "[ERROR] Opción inválida."
            return 1
            ;;
    esac

    echo ""
    echo "[INFO] Creando usuario '$usuario' en el grupo '$grupo'..."

    # Crear usuario del sistema con grupo primario correcto
    sudo useradd -m -d /home/$usuario -s /bin/bash -g $grupo $usuario

    # Establecer contraseña
    echo "$usuario:$password" | sudo chpasswd

    # ── CORRECCIÓN DE ESTRUCTURA DE DIRECTORIOS ───────────────────────────────
    # Con local_root=/srv/ftp/$USER y chroot_local_user=YES, vsftpd hace
    # chroot al directorio /srv/ftp/$usuario y el usuario lo ve como su "/".
    # REGLA: ese directorio raíz del chroot NO puede ser escribible por el
    # usuario (vsftpd lo rechaza). Debe pertenecer a root:root con perms 755.
    # Las carpetas donde el usuario SÍ tiene escritura van DENTRO de él.
    #
    # Estructura resultante que ve el usuario al conectar por FTP:
    #   /              ← chroot raíz, propiedad root:root 755 (solo lectura)
    #   /general       ← enlace/bind al directorio general  (rw para todos)
    #   /reprobados    ← enlace/bind al directorio de grupo  (rw para el grupo)
    #   /nombre_usuario← directorio personal                 (rw solo para él)
    # ─────────────────────────────────────────────────────────────────────────

    # 1. Directorio raíz del chroot: propiedad root, NO escribible por el usuario
    sudo mkdir -p /srv/ftp/$usuario
    sudo chown root:root /srv/ftp/$usuario
    sudo chmod 755 /srv/ftp/$usuario

    # 2. Carpeta personal dentro del chroot (aquí sí puede escribir)
    sudo mkdir -p /srv/ftp/$usuario/$usuario
    sudo chown $usuario:$grupo /srv/ftp/$usuario/$usuario
    sudo chmod 770 /srv/ftp/$usuario/$usuario

    # 3. Subdirectorio general dentro del chroot (bind mount o enlace)
    #    Usamos mount --bind para que los cambios sean reales en /srv/ftp/general
    sudo mkdir -p /srv/ftp/$usuario/general
    sudo chown root:root /srv/ftp/$usuario/general
    sudo chmod 755 /srv/ftp/$usuario/general
    if ! mountpoint -q /srv/ftp/$usuario/general 2>/dev/null; then
        sudo mount --bind /srv/ftp/general /srv/ftp/$usuario/general
    fi

    # 4. Subdirectorio de grupo dentro del chroot (bind mount)
    sudo mkdir -p /srv/ftp/$usuario/$grupo
    sudo chown root:$grupo /srv/ftp/$usuario/$grupo
    sudo chmod 775 /srv/ftp/$usuario/$grupo
    if ! mountpoint -q /srv/ftp/$usuario/$grupo 2>/dev/null; then
        sudo mount --bind /srv/ftp/$grupo /srv/ftp/$usuario/$grupo
    fi

    # 5. Hacer los bind mounts persistentes en /etc/fstab
    #    (se agrega solo si la línea no existe ya)
    if ! grep -q "/srv/ftp/$usuario/general" /etc/fstab; then
        echo "/srv/ftp/general  /srv/ftp/$usuario/general  none  bind  0 0" | sudo tee -a /etc/fstab > /dev/null
    fi
    if ! grep -q "/srv/ftp/$usuario/$grupo" /etc/fstab; then
        echo "/srv/ftp/$grupo  /srv/ftp/$usuario/$grupo  none  bind  0 0" | sudo tee -a /etc/fstab > /dev/null
    fi

    # 6. Agregar usuario a la lista permitida de vsftpd
    if ! grep -q "^$usuario$" /etc/vsftpd/user_list 2>/dev/null; then
        echo "$usuario" | sudo tee -a /etc/vsftpd/user_list > /dev/null
    fi

    # 7. Recargar vsftpd para que tome los cambios
    sudo systemctl reload vsftpd 2>/dev/null || sudo systemctl restart vsftpd

    echo ""
    echo "=========================================="
    echo "[OK] Usuario creado exitosamente"
    echo "=========================================="
    echo "  Usuario:   $usuario"
    echo "  Grupo:     $grupo"
    echo ""
    echo "  Estructura visible al conectar por FTP:"
    echo "    /                  (raíz — solo lectura)"
    echo "    /general           (lectura/escritura — todos)"
    echo "    /$grupo            (lectura/escritura — grupo $grupo)"
    echo "    /$usuario          (lectura/escritura — solo $usuario)"
    echo "=========================================="
}

# Función para dar de baja un usuario FTP
function baja_usuario() {
    echo ""
    echo "=== BAJA DE USUARIO FTP ==="
    echo ""

    read -p "Nombre de usuario a eliminar: " usuario

    if ! validar_usuario "$usuario"; then
        return 1
    fi

    if ! id "$usuario" &>/dev/null; then
        echo "[ERROR] El usuario '$usuario' no existe."
        return 1
    fi

    echo ""
    echo "ADVERTENCIA: Se eliminará el usuario '$usuario' y todos sus archivos."
    read -p "¿Está seguro? (s/n): " confirmacion

    if [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
        echo "[INFO] Operación cancelada."
        return 0
    fi

    echo ""
    echo "[INFO] Eliminando usuario '$usuario'..."

    # Desmontar bind mounts antes de eliminar
    grupo=$(id -gn $usuario 2>/dev/null)
    if mountpoint -q /srv/ftp/$usuario/general 2>/dev/null; then
        sudo umount /srv/ftp/$usuario/general
    fi
    if [ -n "$grupo" ] && mountpoint -q /srv/ftp/$usuario/$grupo 2>/dev/null; then
        sudo umount /srv/ftp/$usuario/$grupo
    fi

    # Limpiar entradas de fstab
    sudo sed -i "/\/srv\/ftp\/$usuario\//d" /etc/fstab

    # Eliminar directorio chroot del usuario
    sudo rm -rf /srv/ftp/$usuario

    # Eliminar usuario del sistema (con su home)
    sudo userdel -r $usuario 2>/dev/null

    # Eliminar de la lista de usuarios permitidos
    sudo sed -i "/^$usuario$/d" /etc/vsftpd/user_list

    sudo systemctl reload vsftpd 2>/dev/null || sudo systemctl restart vsftpd

    echo "[OK] Usuario '$usuario' eliminado correctamente."
}

# Función para cambiar de grupo a un usuario
function cambiar_grupo_usuario() {
    echo ""
    echo "=== CAMBIO DE GRUPO DE USUARIO ==="
    echo ""

    read -p "Nombre de usuario: " usuario

    if ! validar_usuario "$usuario"; then
        return 1
    fi

    if ! id "$usuario" &>/dev/null; then
        echo "[ERROR] El usuario '$usuario' no existe."
        return 1
    fi

    grupo_actual=$(id -gn $usuario)
    echo ""
    echo "Grupo actual: $grupo_actual"
    echo ""
    echo "Seleccione el nuevo grupo:"
    echo "  1. reprobados"
    echo "  2. recursadores"
    read -p "Opción (1 o 2): " grupo_opcion

    case $grupo_opcion in
        1) nuevo_grupo="reprobados" ;;
        2) nuevo_grupo="recursadores" ;;
        *)
            echo "[ERROR] Opción inválida."
            return 1
            ;;
    esac

    if [ "$grupo_actual" == "$nuevo_grupo" ]; then
        echo "[INFO] El usuario ya pertenece al grupo '$nuevo_grupo'."
        return 0
    fi

    echo ""
    echo "[INFO] Cambiando usuario '$usuario' al grupo '$nuevo_grupo'..."

    # Desmontar bind mount del grupo anterior
    if mountpoint -q /srv/ftp/$usuario/$grupo_actual 2>/dev/null; then
        sudo umount /srv/ftp/$usuario/$grupo_actual
    fi
    sudo rm -rf /srv/ftp/$usuario/$grupo_actual
    sudo sed -i "/\/srv\/ftp\/$usuario\/$grupo_actual/d" /etc/fstab

    # Cambiar grupo primario del usuario
    sudo usermod -g $nuevo_grupo $usuario

    # Actualizar permisos del directorio personal
    sudo chown $usuario:$nuevo_grupo /srv/ftp/$usuario/$usuario

    # Montar la carpeta del nuevo grupo
    sudo mkdir -p /srv/ftp/$usuario/$nuevo_grupo
    sudo chown root:$nuevo_grupo /srv/ftp/$usuario/$nuevo_grupo
    sudo chmod 775 /srv/ftp/$usuario/$nuevo_grupo
    if ! mountpoint -q /srv/ftp/$usuario/$nuevo_grupo 2>/dev/null; then
        sudo mount --bind /srv/ftp/$nuevo_grupo /srv/ftp/$usuario/$nuevo_grupo
    fi
    if ! grep -q "/srv/ftp/$usuario/$nuevo_grupo" /etc/fstab; then
        echo "/srv/ftp/$nuevo_grupo  /srv/ftp/$usuario/$nuevo_grupo  none  bind  0 0" | sudo tee -a /etc/fstab > /dev/null
    fi

    sudo systemctl reload vsftpd 2>/dev/null || sudo systemctl restart vsftpd

    echo "[OK] Usuario '$usuario' ahora pertenece al grupo '$nuevo_grupo'."
    echo "     La carpeta /$nuevo_grupo ya está disponible en su sesión FTP."
}

# Función para listar usuarios FTP
function listar_usuarios_ftp() {
    echo ""
    echo "=== USUARIOS FTP REGISTRADOS ==="
    echo ""

    if [ ! -f /etc/vsftpd/user_list ] || [ ! -s /etc/vsftpd/user_list ]; then
        echo "No hay usuarios FTP registrados."
        return 0
    fi

    echo "╔══════════════════╦══════════════════╦═══════════════════════════════════╗"
    echo "║ Usuario          ║ Grupo            ║ Directorio Chroot                 ║"
    echo "╠══════════════════╬══════════════════╬═══════════════════════════════════╣"

    total=0
    while IFS= read -r usuario; do
        [ -z "$usuario" ] && continue
        [[ "$usuario" =~ ^#.* ]] && continue
        [ "$usuario" == "ftp" ] && continue   # omitir el anónimo en la lista
        if id "$usuario" &>/dev/null; then
            grupo=$(id -gn $usuario)
            if [ "$grupo" == "reprobados" ] || [ "$grupo" == "recursadores" ]; then
                dir="/srv/ftp/$usuario"
                printf "║ %-16s ║ %-16s ║ %-33s ║\n" "$usuario" "$grupo" "$dir"
                ((total++))
            fi
        fi
    done < <(sudo cat /etc/vsftpd/user_list 2>/dev/null)

    echo "╚══════════════════╩══════════════════╩═══════════════════════════════════╝"
    echo ""
    echo "Total de usuarios FTP: $total"
    echo ""
    echo "Grupos disponibles:"
    echo "  reprobados:  $(getent group reprobados | cut -d: -f4)"
    echo "  recursadores: $(getent group recursadores | cut -d: -f4)"
}

# Función para ver permisos de un usuario específico
function ver_permisos_usuario() {
    echo ""
    echo "=== PERMISOS DE USUARIO FTP ==="
    echo ""

    read -p "Nombre de usuario: " usuario

    if ! validar_usuario "$usuario"; then
        return 1
    fi

    if ! id "$usuario" &>/dev/null; then
        echo "[ERROR] El usuario '$usuario' no existe."
        return 1
    fi

    grupo=$(id -gn $usuario)

    echo ""
    echo "=========================================="
    echo "INFORMACIÓN DEL USUARIO: $usuario"
    echo "=========================================="
    echo "Grupo primario: $grupo"
    echo "UID: $(id -u $usuario)  |  GID: $(id -g $usuario)"
    echo ""
    echo "ESTRUCTURA FTP (vista dentro del chroot):"
    echo "=========================================="
    echo ""

    for dir in "" "/general" "/$grupo" "/$usuario"; do
        ruta="/srv/ftp/$usuario$dir"
        label="/"
        [ -n "$dir" ] && label="$dir"

        if [ -d "$ruta" ]; then
            perms=$(stat -c "%A  %U:%G" "$ruta")
            mount_info=""
            mountpoint -q "$ruta" 2>/dev/null && mount_info=" [bind mount]"
            printf "  %-20s  %s%s\n" "$label" "$perms" "$mount_info"
        else
            printf "  %-20s  [NO EXISTE]\n" "$label"
        fi
    done

    echo ""
    echo "=========================================="
}

# Función para crear múltiples usuarios
function alta_masiva_usuarios() {
    echo ""
    echo "=== ALTA MASIVA DE USUARIOS FTP ==="
    echo ""

    read -p "¿Cuántos usuarios desea crear? " cantidad

    if ! [[ "$cantidad" =~ ^[0-9]+$ ]] || [ "$cantidad" -lt 1 ]; then
        echo "[ERROR] Cantidad inválida."
        return 1
    fi

    echo ""
    for ((i=1; i<=cantidad; i++)); do
        echo "----------------------------------------"
        echo "Usuario $i de $cantidad"
        echo "----------------------------------------"
        alta_usuario
        echo ""
    done

    echo ""
    echo "[OK] Proceso de alta masiva completado."
    echo ""
    listar_usuarios_ftp
}