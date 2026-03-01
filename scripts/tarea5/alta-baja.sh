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
    
    # Verificar si el usuario ya existe
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
        1)
            grupo="reprobados"
            ;;
        2)
            grupo="recursadores"
            ;;
        *)
            echo "[ERROR] Opción inválida."
            return 1
            ;;
    esac
    
    echo ""
    echo "[INFO] Creando usuario '$usuario' en el grupo '$grupo'..."
    
    # Crear usuario del sistema
    sudo useradd -m -d /home/$usuario -s /bin/bash -G $grupo $usuario
    
    # Establecer contraseña
    echo "$usuario:$password" | sudo chpasswd
    
    # Crear directorio personal del usuario en FTP
    sudo mkdir -p /srv/ftp/usuarios/$usuario
    sudo chown $usuario:$grupo /srv/ftp/usuarios/$usuario
    sudo chmod 770 /srv/ftp/usuarios/$usuario
    
    # Crear enlaces simbólicos en el home del usuario para estructura FTP
    sudo mkdir -p /home/$usuario/ftp
    sudo ln -sf /srv/ftp/general /home/$usuario/ftp/general
    sudo ln -sf /srv/ftp/$grupo /home/$usuario/ftp/$grupo
    sudo ln -sf /srv/ftp/usuarios/$usuario /home/$usuario/ftp/mi_carpeta
    
    # Agregar usuario a la lista de usuarios permitidos en vsftpd
    if ! grep -q "^$usuario$" /etc/vsftpd/user_list 2>/dev/null; then
        echo "$usuario" | sudo tee -a /etc/vsftpd/user_list > /dev/null
    fi
    
    echo ""
    echo "=========================================="
    echo "[OK] Usuario creado exitosamente"
    echo "=========================================="
    echo "  Usuario: $usuario"
    echo "  Grupo: $grupo"
    echo "  Directorio personal: /srv/ftp/usuarios/$usuario"
    echo "  Acceso a:"
    echo "    • /srv/ftp/general (lectura/escritura)"
    echo "    • /srv/ftp/$grupo (lectura/escritura)"
    echo "    • /srv/ftp/usuarios/$usuario (lectura/escritura)"
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
    
    # Verificar si el usuario existe
    if ! id "$usuario" &>/dev/null; then
        echo "[ERROR] El usuario '$usuario' no existe."
        return 1
    fi
    
    echo ""
    echo "⚠️  ADVERTENCIA: Se eliminará el usuario '$usuario' y todos sus archivos."
    read -p "¿Está seguro? (s/n): " confirmacion
    
    if [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
        echo "[INFO] Operación cancelada."
        return 0
    fi
    
    echo ""
    echo "[INFO] Eliminando usuario '$usuario'..."
    
    # Eliminar directorio personal de FTP
    sudo rm -rf /srv/ftp/usuarios/$usuario
    
    # Eliminar usuario del sistema (con su home)
    sudo userdel -r $usuario 2>/dev/null
    
    # Eliminar de la lista de usuarios permitidos
    sudo sed -i "/^$usuario$/d" /etc/vsftpd/user_list
    
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
    
    # Verificar si el usuario existe
    if ! id "$usuario" &>/dev/null; then
        echo "[ERROR] El usuario '$usuario' no existe."
        return 1
    fi
    
    # Obtener grupo actual
    grupo_actual=$(id -gn $usuario)
    echo ""
    echo "Grupo actual: $grupo_actual"
    echo ""
    echo "Seleccione el nuevo grupo:"
    echo "  1. reprobados"
    echo "  2. recursadores"
    read -p "Opción (1 o 2): " grupo_opcion
    
    case $grupo_opcion in
        1)
            nuevo_grupo="reprobados"
            ;;
        2)
            nuevo_grupo="recursadores"
            ;;
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
    
    # Cambiar grupo primario del usuario
    sudo usermod -g $nuevo_grupo $usuario
    
    # Actualizar permisos del directorio personal
    sudo chown $usuario:$nuevo_grupo /srv/ftp/usuarios/$usuario
    
    # Actualizar enlaces simbólicos
    sudo rm -f /home/$usuario/ftp/$grupo_actual
    sudo ln -sf /srv/ftp/$nuevo_grupo /home/$usuario/ftp/$nuevo_grupo
    
    echo "[OK] Usuario '$usuario' ahora pertenece al grupo '$nuevo_grupo'."
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
    
    echo "╔════════════════╦═══════════════╦════════════════════════════════╗"
    echo "║ Usuario        ║ Grupo         ║ Directorio Personal            ║"
    echo "╠════════════════╬═══════════════╬════════════════════════════════╣"
    
    while IFS= read -r usuario; do
        if id "$usuario" &>/dev/null; then
            grupo=$(id -gn $usuario)
            dir="/srv/ftp/usuarios/$usuario"
            printf "║ %-14s ║ %-13s ║ %-30s ║\n" "$usuario" "$grupo" "$dir"
        fi
    done < /etc/vsftpd/user_list
    
    echo "╚════════════════╩═══════════════╩════════════════════════════════╝"
    echo ""
    
    # Contar usuarios
    total=$(wc -l < /etc/vsftpd/user_list 2>/dev/null || echo 0)
    echo "Total de usuarios FTP: $total"
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
    grupos_secundarios=$(id -Gn $usuario)
    
    echo ""
    echo "=========================================="
    echo "INFORMACIÓN DEL USUARIO: $usuario"
    echo "=========================================="
    echo "Grupo primario: $grupo"
    echo "Grupos secundarios: $grupos_secundarios"
    echo "UID: $(id -u $usuario)"
    echo "GID: $(id -g $usuario)"
    echo ""
    echo "PERMISOS EN DIRECTORIOS FTP:"
    echo "=========================================="
    echo ""
    
    # Verificar permisos en cada directorio
    echo "1. Directorio general:"
    if [ -d /srv/ftp/general ]; then
        ls -ld /srv/ftp/general | awk '{print "   Permisos: " $1 "  Propietario: " $3 "  Grupo: " $4}'
        if [ -w /srv/ftp/general ]; then
            echo "   Acceso: ✓ Lectura/Escritura"
        elif [ -r /srv/ftp/general ]; then
            echo "   Acceso: ✓ Solo lectura"
        else
            echo "   Acceso: ✗ Sin acceso"
        fi
    fi
    
    echo ""
    echo "2. Directorio de grupo ($grupo):"
    if [ -d /srv/ftp/$grupo ]; then
        ls -ld /srv/ftp/$grupo | awk '{print "   Permisos: " $1 "  Propietario: " $3 "  Grupo: " $4}'
        sudo -u $usuario test -w /srv/ftp/$grupo && echo "   Acceso: ✓ Lectura/Escritura" || echo "   Acceso: ✓ Solo lectura"
    fi
    
    echo ""
    echo "3. Directorio personal:"
    if [ -d /srv/ftp/usuarios/$usuario ]; then
        ls -ld /srv/ftp/usuarios/$usuario | awk '{print "   Permisos: " $1 "  Propietario: " $3 "  Grupo: " $4}'
        echo "   Acceso: ✓ Lectura/Escritura (propietario)"
    else
        echo "   ✗ Directorio no existe"
    fi
    
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
    echo "Se crearán $cantidad usuarios."
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