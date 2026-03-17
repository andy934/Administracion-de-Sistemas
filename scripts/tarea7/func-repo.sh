#!/usr/bin/env bash
# =============================================================================
# func-repo.sh - Gestion del repositorio FTP para instalacion hibrida
# Practica 7 - Administracion de Sistemas
# Sistema: Rocky Linux 9
# =============================================================================

# =============================================================================
# CONFIGURACION GLOBAL DEL REPOSITORIO
# =============================================================================

REPO_BASE="/srv/ftp/repo"
REPO_LINUX="$REPO_BASE/http/Linux"
REPO_USER="ftprepo"
REPO_PASS="Repo@2026"
FTP_HOST="127.0.0.1"

DIR_APACHE="$REPO_LINUX/Apache"
DIR_NGINX="$REPO_LINUX/Nginx"
DIR_TOMCAT="$REPO_LINUX/Tomcat"

# =============================================================================
# VALIDACIONES DE DEPENDENCIAS (internas)
# =============================================================================

_validar_vsftpd() {
    if systemctl is-active vsftpd &>/dev/null; then
        return 0
    fi
    warn "vsftpd no esta activo (requerido para el repositorio FTP)"
    read -rp "  Iniciar vsftpd ahora? [S/n]: " r
    [[ "$r" =~ ^[nN]$ ]] && return 1
    systemctl start vsftpd
    if systemctl is-active vsftpd &>/dev/null; then
        ok "vsftpd iniciado"
        return 0
    fi
    err "No se pudo iniciar vsftpd"
    return 1
}

repo_esta_listo() {
    [ -d "$DIR_APACHE" ] && [ -d "$DIR_NGINX" ] && [ -d "$DIR_TOMCAT" ] && \
    [ "$(ls "$DIR_APACHE" 2>/dev/null | grep -vc '\.sha256$')" -gt 0 ] && \
    [ "$(ls "$DIR_NGINX"  2>/dev/null | grep -vc '\.sha256$')" -gt 0 ] && \
    [ "$(ls "$DIR_TOMCAT" 2>/dev/null | grep -vc '\.sha256$')" -gt 0 ]
}

_validar_repo() {
    if repo_esta_listo; then
        return 0
    fi
    warn "El repositorio FTP no esta poblado aun"
    read -rp "  Preparar repositorio ahora? [S/n]: " r
    [[ "$r" =~ ^[nN]$ ]] && return 1
    preparar_repositorio_completo
    return $?
}

# =============================================================================
# CREAR USUARIO FTP DEL REPOSITORIO
# =============================================================================

crear_usuario_repo() {
    info "Configurando usuario FTP del repositorio: $REPO_USER"

    if id "$REPO_USER" &>/dev/null; then
        info "Usuario $REPO_USER ya existe"
    else
        useradd -m -d "$REPO_BASE" -s /sbin/nologin "$REPO_USER"
        echo "$REPO_USER:$REPO_PASS" | chpasswd
        ok "Usuario $REPO_USER creado (pass: $REPO_PASS)"
    fi

    local userlist="/etc/vsftpd/user_list"
    if [ -f "$userlist" ] && ! grep -q "^$REPO_USER$" "$userlist"; then
        echo "$REPO_USER" >> "$userlist"
        ok "Usuario agregado a $userlist"
    fi

    mkdir -p /etc/vsftpd/users
    cat > "/etc/vsftpd/users/$REPO_USER" <<EOF
local_root=$REPO_BASE
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
EOF
    ok "Configuracion vsftpd per-user escrita"
}

# =============================================================================
# CREAR ESTRUCTURA DE DIRECTORIOS
# =============================================================================

crear_estructura_repo() {
    info "Creando estructura de directorios del repositorio..."
    mkdir -p "$DIR_APACHE" "$DIR_NGINX" "$DIR_TOMCAT"
    chown -R "$REPO_USER":"$REPO_USER" "$REPO_BASE" 2>/dev/null || \
        chown -R "$REPO_USER":ftp "$REPO_BASE" 2>/dev/null || true
    chmod -R 755 "$REPO_BASE"
    ok "Estructura lista: $DIR_APACHE | $DIR_NGINX | $DIR_TOMCAT"
}

# =============================================================================
# DESCARGAR CON PROGRESO
# =============================================================================

_descargar() {
    local url="$1" dest="$2" nombre="$3"
    info "Descargando $nombre..."
    if curl -fL --progress-bar -o "$dest" "$url" 2>/dev/null; then
        ok "$nombre descargado"
        return 0
    fi
    err "Fallo la descarga de $nombre"
    rm -f "$dest"
    return 1
}

# =============================================================================
# POBLAR REPOSITORIO CON BINARIOS Y HASHES
# =============================================================================

poblar_repositorio() {
    info "Poblando repositorio con binarios..."
    echo ""
    local errores=0

    # ── Apache ──────────────────────────────────────────────────────────────
    local apache_ver
    apache_ver=$(curl -s https://downloads.apache.org/httpd/ 2>/dev/null \
        | grep -oP 'httpd-2\.4\.\d+\.tar\.bz2' \
        | sort -t. -k3 -n | tail -1)

    if [ -n "$apache_ver" ]; then
        local adest="$DIR_APACHE/$apache_ver"
        if [ ! -f "$adest" ]; then
            _descargar "https://downloads.apache.org/httpd/$apache_ver" \
                "$adest" "Apache $apache_ver" && \
            sha256sum "$adest" | awk '{print $1}' > "${adest}.sha256" && \
            ok "Hash generado: ${apache_ver}.sha256" || errores=$((errores+1))
        else
            info "Apache $apache_ver ya existe en el repositorio"
        fi
    else
        warn "No se pudo detectar version actual de Apache"
        errores=$((errores+1))
    fi

    # ── Nginx ────────────────────────────────────────────────────────────────
    local nginx_ver
    nginx_ver=$(curl -s https://nginx.org/en/download.html 2>/dev/null \
        | grep -oP 'nginx-1\.\d*[02468]\.\d+\.tar\.gz' \
        | sort -t. -k2 -n -k3 -n | tail -1)

    if [ -n "$nginx_ver" ]; then
        local ndest="$DIR_NGINX/$nginx_ver"
        if [ ! -f "$ndest" ]; then
            _descargar "https://nginx.org/download/$nginx_ver" \
                "$ndest" "Nginx $nginx_ver" && \
            sha256sum "$ndest" | awk '{print $1}' > "${ndest}.sha256" && \
            ok "Hash generado: ${nginx_ver}.sha256" || errores=$((errores+1))
        else
            info "Nginx $nginx_ver ya existe en el repositorio"
        fi
    else
        warn "No se pudo detectar version actual de Nginx"
        errores=$((errores+1))
    fi

    # ── Tomcat ───────────────────────────────────────────────────────────────
    local tomcat_ver
    tomcat_ver=$(curl -s https://downloads.apache.org/tomcat/tomcat-10/ 2>/dev/null \
        | grep -oP 'v10\.\d+\.\d+' | sort -t. -k2 -n -k3 -n | tail -1)

    if [ -n "$tomcat_ver" ]; then
        local tv="${tomcat_ver#v}"
        local tfile="apache-tomcat-${tv}.tar.gz"
        local tdest="$DIR_TOMCAT/$tfile"
        if [ ! -f "$tdest" ]; then
            _descargar \
                "https://downloads.apache.org/tomcat/tomcat-10/${tomcat_ver}/bin/$tfile" \
                "$tdest" "Tomcat $tv" && \
            sha256sum "$tdest" | awk '{print $1}' > "${tdest}.sha256" && \
            ok "Hash generado: ${tfile}.sha256" || errores=$((errores+1))
        else
            info "Tomcat $tv ya existe en el repositorio"
        fi
    else
        warn "No se pudo detectar version actual de Tomcat"
        errores=$((errores+1))
    fi

    chown -R "$REPO_USER":"$REPO_USER" "$REPO_BASE" 2>/dev/null || true
    chmod -R 755 "$REPO_BASE"
    echo ""

    if [ "$errores" -eq 0 ]; then
        ok "Repositorio FTP listo en $REPO_BASE"
    else
        warn "Repositorio listo con $errores advertencias"
    fi
    return "$errores"
}

# =============================================================================
# FLUJO COMPLETO: USUARIO + ESTRUCTURA + BINARIOS
# =============================================================================

preparar_repositorio_completo() {
    _validar_vsftpd || return 1
    crear_usuario_repo
    crear_estructura_repo
    poblar_repositorio
    systemctl restart vsftpd
    ok "Repositorio FTP completamente preparado"
}

# =============================================================================
# CLIENTE FTP: LISTAR DIRECTORIO
# =============================================================================

listar_ftp() {
    curl -s --user "$REPO_USER:$REPO_PASS" \
         "ftp://${FTP_HOST}/${1}/" 2>/dev/null \
    | awk '{print $NF}'
}

# =============================================================================
# CLIENTE FTP: DESCARGAR ARCHIVO
# =============================================================================

descargar_ftp() {
    local ruta="$1" dest="$2"
    info "Descargando desde FTP: ftp://${FTP_HOST}/${ruta}"
    curl -fL --progress-bar \
         --user "$REPO_USER:$REPO_PASS" \
         "ftp://${FTP_HOST}/${ruta}" \
         -o "$dest" 2>/dev/null

    if [ $? -eq 0 ] && [ -s "$dest" ]; then
        ok "Descarga completada: $(basename "$dest")"
        return 0
    fi
    err "Fallo la descarga: $ruta"
    rm -f "$dest"
    return 1
}

# =============================================================================
# VERIFICAR INTEGRIDAD SHA256
# =============================================================================

verificar_hash() {
    local archivo="$1" ruta_hash="$2"
    local tmp_hash="/tmp/$(basename "$archivo").sha256.tmp"

    info "Verificando integridad de $(basename "$archivo")..."

    descargar_ftp "$ruta_hash" "$tmp_hash" || {
        err "No se pudo obtener el archivo de hash del servidor FTP"
        return 1
    }

    local hash_remoto hash_local
    hash_remoto=$(tr -d '[:space:]' < "$tmp_hash")
    hash_local=$(sha256sum "$archivo" | awk '{print $1}')
    rm -f "$tmp_hash"

    echo "  Hash esperado : $hash_remoto"
    echo "  Hash calculado: $hash_local"

    if [ "$hash_local" = "$hash_remoto" ]; then
        ok "Integridad verificada correctamente"
        return 0
    fi
    err "Hash NO coincide — archivo posiblemente corrupto"
    return 1
}

# =============================================================================
# NAVEGACION INTERACTIVA DEL REPOSITORIO FTP
# =============================================================================

seleccionar_desde_ftp() {
    # $1 = Apache | Nginx | Tomcat
    # Exporta: ARCHIVO_FTP_SELECCIONADO, RUTA_FTP_SELECCIONADA
    local servicio="$1"
    local ruta="http/Linux/$servicio"

    echo ""
    info "Navegando repositorio FTP: /$ruta"
    echo ""

    local archivos=()
    while IFS= read -r linea; do
        [[ "$linea" == *.sha256 || -z "$linea" ]] && continue
        archivos+=("$linea")
    done < <(listar_ftp "$ruta")

    if [ ${#archivos[@]} -eq 0 ]; then
        err "No hay archivos en el repositorio para $servicio"
        err "Ejecuta primero: Opcion 1 - Preparar repositorio FTP"
        return 1
    fi

    echo -e "${CYAN}  Archivos disponibles en FTP/$servicio:${NC}"
    for i in "${!archivos[@]}"; do
        printf "    %d. %s\n" "$((i+1))" "${archivos[$i]}"
    done
    echo ""

    local sel=0
    while ! [[ "$sel" =~ ^[0-9]+$ ]] || \
          [ "$sel" -lt 1 ] || [ "$sel" -gt "${#archivos[@]}" ]; do
        read -rp "  Seleccione archivo (1-${#archivos[@]}): " sel
    done

    ARCHIVO_FTP_SELECCIONADO="${archivos[$((sel-1))]}"
    RUTA_FTP_SELECCIONADA="$ruta/$ARCHIVO_FTP_SELECCIONADO"
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
    printf "  %-12s %-10s %-10s\n" "Servicio" "Binarios" "Hashes"
    echo "  ────────────────────────────────────"

    for svc in Apache Nginx Tomcat; do
        local dir="$REPO_LINUX/$svc"
        local bins=0 hashes=0
        if [ -d "$dir" ]; then
            bins=$(ls "$dir" 2>/dev/null | grep -vc '\.sha256$')
            hashes=$(ls "$dir" 2>/dev/null | grep -c '\.sha256$')
        fi
        printf "  %-12s %-10s %-10s\n" "$svc" "$bins" "$hashes"
        [ -d "$dir" ] && ls "$dir" 2>/dev/null | grep -v '\.sha256$' | \
            sed 's/^/               - /'
    done

    echo ""
    local st; st=$(systemctl is-active vsftpd 2>/dev/null)
    local col="${RED}"; [ "$st" = "active" ] && col="${GREEN}"
    printf "  vsftpd: %b%s%b\n" "$col" "$st" "$NC"
    echo ""
}