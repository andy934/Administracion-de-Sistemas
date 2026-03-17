#!/usr/bin/env bash
# =============================================================================
# func-repo.sh - Gestion del repositorio FTP para instalacion hibrida
# Practica 7 - Administracion de Sistemas
# Sistema: Rocky Linux 9
# =============================================================================

# Colores (compatibles con func de P6)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# CONFIGURACION DEL REPOSITORIO
# =============================================================================

REPO_BASE="/srv/ftp/repo"
REPO_LINUX="$REPO_BASE/http/Linux"
REPO_USER="ftprepo"
REPO_PASS="Repo@2026"
FTP_HOST="127.0.0.1"

# Directorios por servicio
DIR_APACHE="$REPO_LINUX/Apache"
DIR_NGINX="$REPO_LINUX/Nginx"
DIR_TOMCAT="$REPO_LINUX/Tomcat"

# =============================================================================
# CREAR USUARIO FTP DEL REPOSITORIO
# =============================================================================

crear_usuario_repo() {
    info "Configurando usuario FTP para repositorio: $REPO_USER"

    if id "$REPO_USER" &>/dev/null; then
        info "Usuario $REPO_USER ya existe."
    else
        useradd -m -d "$REPO_BASE" -s /sbin/nologin "$REPO_USER"
        echo "$REPO_USER:$REPO_PASS" | chpasswd
        ok "Usuario $REPO_USER creado."
    fi

    # Asegurar que vsftpd permita este usuario
    local userlist="/etc/vsftpd/user_list"
    if [ -f "$userlist" ] && ! grep -q "^$REPO_USER$" "$userlist"; then
        echo "$REPO_USER" >> "$userlist"
        ok "Usuario $REPO_USER agregado a user_list de vsftpd."
    fi

    # Archivo de configuracion por usuario
    local userconf="/etc/vsftpd/users/$REPO_USER"
    cat > "$userconf" <<EOF
local_root=$REPO_BASE
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
EOF
    ok "Configuracion per-user escrita en $userconf"
}

# =============================================================================
# CREAR ESTRUCTURA DE DIRECTORIOS DEL REPOSITORIO
# =============================================================================

crear_estructura_repo() {
    info "Creando estructura del repositorio FTP..."

    mkdir -p "$DIR_APACHE" "$DIR_NGINX" "$DIR_TOMCAT"
    chown -R "$REPO_USER":ftp "$REPO_BASE" 2>/dev/null || \
        chown -R "$REPO_USER":"$REPO_USER" "$REPO_BASE"
    chmod -R 755 "$REPO_BASE"

    ok "Estructura creada:"
    ok "  $DIR_APACHE"
    ok "  $DIR_NGINX"
    ok "  $DIR_TOMCAT"
}

# =============================================================================
# POBLAR REPOSITORIO - DESCARGAR BINARIOS Y GENERAR SHA256
# =============================================================================

poblar_repositorio() {
    info "Poblando repositorio FTP con binarios e instaladores..."
    echo ""

    # ── Apache ──────────────────────────────────────────────────────────────
    info "Descargando Apache HTTPD para repositorio..."
    local apache_ver
    apache_ver=$(curl -s https://downloads.apache.org/httpd/ 2>/dev/null \
        | grep -oP 'httpd-2\.4\.\d+\.tar\.bz2' \
        | sort -t. -k3 -n | tail -1)

    if [ -n "$apache_ver" ]; then
        local apache_url="https://downloads.apache.org/httpd/$apache_ver"
        local apache_dest="$DIR_APACHE/$apache_ver"
        if [ ! -f "$apache_dest" ]; then
            curl -s -o "$apache_dest" "$apache_url"
            sha256sum "$apache_dest" | awk '{print $1}' > "${apache_dest}.sha256"
            ok "Apache: $apache_ver + sha256 generado"
        else
            info "Apache: $apache_ver ya existe en repositorio"
        fi
    else
        warn "No se pudo obtener version de Apache desde internet"
    fi

    # ── Nginx ────────────────────────────────────────────────────────────────
    info "Descargando Nginx para repositorio..."
    local nginx_ver
    nginx_ver=$(curl -s https://nginx.org/en/download.html 2>/dev/null \
        | grep -oP 'nginx-1\.\d*[02468]\.\d+\.tar\.gz' \
        | sort -t. -k2 -n -k3 -n | tail -1)

    if [ -n "$nginx_ver" ]; then
        local nginx_url="https://nginx.org/download/$nginx_ver"
        local nginx_dest="$DIR_NGINX/$nginx_ver"
        if [ ! -f "$nginx_dest" ]; then
            curl -s -o "$nginx_dest" "$nginx_url"
            sha256sum "$nginx_dest" | awk '{print $1}' > "${nginx_dest}.sha256"
            ok "Nginx: $nginx_ver + sha256 generado"
        else
            info "Nginx: $nginx_ver ya existe en repositorio"
        fi
    else
        warn "No se pudo obtener version de Nginx desde internet"
    fi

    # ── Tomcat ───────────────────────────────────────────────────────────────
    info "Descargando Tomcat para repositorio..."
    local tomcat_ver
    tomcat_ver=$(curl -s https://downloads.apache.org/tomcat/tomcat-10/ 2>/dev/null \
        | grep -oP 'v10\.\d+\.\d+' | sort -t. -k2 -n -k3 -n | tail -1)

    if [ -n "$tomcat_ver" ]; then
        local tv="${tomcat_ver#v}"
        local tomcat_file="apache-tomcat-${tv}.tar.gz"
        local tomcat_url="https://downloads.apache.org/tomcat/tomcat-10/${tomcat_ver}/bin/$tomcat_file"
        local tomcat_dest="$DIR_TOMCAT/$tomcat_file"
        if [ ! -f "$tomcat_dest" ]; then
            curl -s -o "$tomcat_dest" "$tomcat_url"
            sha256sum "$tomcat_dest" | awk '{print $1}' > "${tomcat_dest}.sha256"
            ok "Tomcat: $tomcat_file + sha256 generado"
        else
            info "Tomcat: $tomcat_file ya existe en repositorio"
        fi
    else
        warn "No se pudo obtener version de Tomcat desde internet"
    fi

    # Asegurar permisos finales
    chown -R "$REPO_USER":"$REPO_USER" "$REPO_BASE" 2>/dev/null || true
    chmod -R 755 "$REPO_BASE"

    echo ""
    ok "Repositorio FTP listo en $REPO_BASE"
}

# =============================================================================
# LISTAR REPOSITORIO FTP (via curl desde localhost)
# =============================================================================

listar_ftp() {
    # $1 = ruta relativa (ej. "http/Linux/Apache")
    local ruta="${1:-http/Linux}"
    curl -s --user "$REPO_USER:$REPO_PASS" \
         "ftp://${FTP_HOST}/${ruta}/" 2>/dev/null \
    | awk '{print $NF}'
}

# =============================================================================
# DESCARGAR ARCHIVO DEL REPOSITORIO FTP
# =============================================================================

descargar_ftp() {
    # $1 = ruta remota (ej. "http/Linux/Apache/httpd-2.4.63.tar.bz2")
    # $2 = destino local
    local ruta_remota="$1"
    local destino="$2"

    info "Descargando desde FTP: ftp://${FTP_HOST}/${ruta_remota}"
    curl -s --user "$REPO_USER:$REPO_PASS" \
         "ftp://${FTP_HOST}/${ruta_remota}" \
         -o "$destino"

    if [ $? -eq 0 ] && [ -s "$destino" ]; then
        ok "Descarga completada: $destino"
        return 0
    else
        err "Fallo la descarga de $ruta_remota"
        return 1
    fi
}

# =============================================================================
# VERIFICAR INTEGRIDAD SHA256
# =============================================================================

verificar_hash() {
    # $1 = archivo local descargado
    # $2 = ruta remota del .sha256 en el FTP
    local archivo="$1"
    local ruta_sha256="$2"
    local tmp_hash="/tmp/$(basename "$archivo").sha256"

    info "Verificando integridad de $(basename "$archivo")..."

    # Descargar el archivo de hash desde FTP
    descargar_ftp "$ruta_sha256" "$tmp_hash"
    if [ $? -ne 0 ]; then
        err "No se pudo obtener el archivo de hash"
        return 1
    fi

    # El .sha256 contiene solo el hash (sin nombre de archivo)
    local hash_remoto
    hash_remoto=$(cat "$tmp_hash" | tr -d '[:space:]')
    local hash_local
    hash_local=$(sha256sum "$archivo" | awk '{print $1}')

    rm -f "$tmp_hash"

    if [ "$hash_local" = "$hash_remoto" ]; then
        ok "Hash verificado correctamente"
        ok "  Esperado: $hash_remoto"
        ok "  Calculado: $hash_local"
        return 0
    else
        err "Hash NO coincide - archivo corrupto o modificado"
        err "  Esperado: $hash_remoto"
        err "  Calculado: $hash_local"
        return 1
    fi
}

# =============================================================================
# MENU: SELECCION INTERACTIVA DE ARCHIVO EN REPOSITORIO FTP
# =============================================================================

seleccionar_desde_ftp() {
    # $1 = servicio (Apache, Nginx, Tomcat)
    # Retorna: ARCHIVO_FTP_SELECCIONADO (variable global)
    local servicio="$1"
    local ruta_servicio="http/Linux/$servicio"

    echo ""
    info "Navegando repositorio FTP: $ruta_servicio"

    # Listar archivos (excluir .sha256)
    local archivos=()
    while IFS= read -r linea; do
        [[ "$linea" == *.sha256 ]] && continue
        [[ -z "$linea" ]] && continue
        archivos+=("$linea")
    done < <(listar_ftp "$ruta_servicio")

    if [ ${#archivos[@]} -eq 0 ]; then
        err "No se encontraron archivos en el repositorio para $servicio"
        err "Asegurate de haber ejecutado 'Preparar repositorio FTP' primero"
        return 1
    fi

    echo ""
    echo -e "${CYAN}  Archivos disponibles en FTP ($servicio):${NC}"
    for i in "${!archivos[@]}"; do
        echo "    $((i+1)). ${archivos[$i]}"
    done
    echo ""

    local sel=0
    while [ "$sel" -lt 1 ] || [ "$sel" -gt "${#archivos[@]}" ]; do
        read -rp "  Seleccione archivo (1-${#archivos[@]}): " sel
        [[ "$sel" =~ ^[0-9]+$ ]] || sel=0
    done

    ARCHIVO_FTP_SELECCIONADO="${archivos[$((sel-1))]}"
    RUTA_FTP_SELECCIONADA="$ruta_servicio/$ARCHIVO_FTP_SELECCIONADO"
    ok "Seleccionado: $ARCHIVO_FTP_SELECCIONADO"
    return 0
}

# =============================================================================
# MOSTRAR ESTADO DEL REPOSITORIO
# =============================================================================

mostrar_estado_repo() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}   ESTADO DEL REPOSITORIO FTP             ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo ""

    for servicio in Apache Nginx Tomcat; do
        local dir="$REPO_LINUX/$servicio"
        echo -e "  ${BOLD}$servicio:${NC}"
        if [ -d "$dir" ]; then
            local archivos
            archivos=$(ls "$dir" 2>/dev/null | grep -v '\.sha256$' | wc -l)
            local hashes
            hashes=$(ls "$dir" 2>/dev/null | grep '\.sha256$' | wc -l)
            echo "    Binarios : $archivos"
            echo "    Hashes   : $hashes"
            ls "$dir" 2>/dev/null | grep -v '\.sha256$' | \
                sed 's/^/      - /'
        else
            echo "    [no creado]"
        fi
        echo ""
    done

    # Estado vsftpd
    local vsftpd_status
    vsftpd_status=$(systemctl is-active vsftpd 2>/dev/null)
    echo -e "  ${BOLD}vsftpd:${NC} $vsftpd_status"
    echo ""
}