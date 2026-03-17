#!/usr/bin/env bash
# =============================================================================
# func-install.sh - Orquestador de instalacion hibrida (WEB / FTP)
# Practica 7 - Administracion de Sistemas
# Reutiliza funciones de Practica 6 (http-func.sh)
# =============================================================================

# Ruta al repo (relativa al script que hace source de este archivo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P6_FUNC="$SCRIPT_DIR/../tarea6/http-func.sh"
P5_CONF="$SCRIPT_DIR/../tarea5/configuracion.sh"

# Directorio temporal para descargas FTP
INSTALL_TMP="/tmp/tarea7_install"
mkdir -p "$INSTALL_TMP"

# =============================================================================
# PREGUNTAR FUENTE DE INSTALACION
# =============================================================================

elegir_fuente() {
    echo ""
    echo -e "${CYAN}  Fuente de instalacion:${NC}"
    echo "    1. WEB  — descargar desde repositorio oficial en internet"
    echo "    2. FTP  — descargar desde repositorio privado local"
    echo ""
    local fuente=""
    while [[ "$fuente" != "1" && "$fuente" != "2" ]]; do
        read -rp "  Seleccione fuente (1-2): " fuente
    done
    FUENTE_INSTALACION="$fuente"   # "1"=WEB, "2"=FTP
}

# =============================================================================
# VERIFICAR/INSTALAR PREREQUISITOS (servidor limpio)
# =============================================================================

verificar_prerequisitos() {
    info "Verificando prerequisitos del sistema..."

    local paquetes=("curl" "wget" "openssl" "gcc" "make" "tar")
    local faltantes=()
    for pkg in "${paquetes[@]}"; do
        command -v "$pkg" &>/dev/null || faltantes+=("$pkg")
    done

    if [ ${#faltantes[@]} -gt 0 ]; then
        info "Instalando paquetes base: ${faltantes[*]}"
        dnf install -y "${faltantes[@]}" &>/dev/null
        ok "Paquetes instalados"
    else
        ok "Prerequisitos satisfechos"
    fi
}

# =============================================================================
# VERIFICAR/INSTALAR VSFTPD (P5)
# =============================================================================

verificar_vsftpd() {
    if systemctl is-active vsftpd &>/dev/null; then
        ok "vsftpd activo"
        return 0
    fi

    warn "vsftpd no esta activo"
    read -rp "  Instalar/iniciar vsftpd ahora? [S/n]: " resp
    [[ "$resp" =~ ^[nN]$ ]] && return 1

    if [ -f "$P5_CONF" ]; then
        info "Iniciando configuracion de vsftpd (Practica 5)..."
        bash "$P5_CONF"
    else
        info "Instalando vsftpd..."
        dnf install -y vsftpd &>/dev/null
        systemctl enable --now vsftpd
        ok "vsftpd instalado e iniciado"
    fi
}

# =============================================================================
# INSTALAR SERVICIO DESDE WEB (delega a P6)
# =============================================================================

instalar_desde_web() {
    local servicio="$1"   # apache | nginx | tomcat

    if [ ! -f "$P6_FUNC" ]; then
        err "No se encontro $P6_FUNC"
        err "Asegurate de que la estructura del repo sea correcta"
        return 1
    fi

    info "Cargando funciones de instalacion (Practica 6)..."
    # shellcheck source=/dev/null
    source "$P6_FUNC"

    case "$servicio" in
        apache)
            info "Instalando Apache HTTPD desde WEB..."
            listar_versiones_apache
            instalar_apache
            ;;
        nginx)
            info "Instalando Nginx desde WEB..."
            listar_versiones_nginx
            instalar_nginx
            ;;
        tomcat)
            info "Instalando Tomcat desde WEB..."
            listar_versiones_tomcat
            instalar_tomcat
            ;;
        *)
            err "Servicio desconocido: $servicio"
            return 1
            ;;
    esac
}

# =============================================================================
# INSTALAR SERVICIO DESDE FTP
# =============================================================================

instalar_desde_ftp() {
    local servicio="$1"   # apache | nginx | tomcat

    # Capitalizar para coincidir con estructura FTP
    local svc_dir
    case "$servicio" in
        apache) svc_dir="Apache" ;;
        nginx)  svc_dir="Nginx"  ;;
        tomcat) svc_dir="Tomcat" ;;
        *)      err "Servicio desconocido: $servicio"; return 1 ;;
    esac

    # Navegar FTP y seleccionar archivo
    seleccionar_desde_ftp "$svc_dir"
    if [ $? -ne 0 ]; then
        err "No se pudo seleccionar archivo del repositorio FTP"
        return 1
    fi

    # Descargar binario
    local destino="$INSTALL_TMP/$ARCHIVO_FTP_SELECCIONADO"
    descargar_ftp "$RUTA_FTP_SELECCIONADA" "$destino"
    if [ $? -ne 0 ]; then
        err "Error en la descarga del binario"
        return 1
    fi

    # Verificar hash
    local ruta_hash="${RUTA_FTP_SELECCIONADA}.sha256"
    verificar_hash "$destino" "$ruta_hash"
    if [ $? -ne 0 ]; then
        err "Verificacion de integridad fallida"
        read -rp "  Continuar de todas formas? [s/N]: " forzar
        [[ "$forzar" =~ ^[sS]$ ]] || return 1
    fi

    # Instalar segun tipo de archivo
    info "Instalando $servicio desde archivo local: $destino"
    case "$servicio" in
        apache) instalar_apache_desde_tarball "$destino" ;;
        nginx)  instalar_nginx_desde_tarball  "$destino" ;;
        tomcat) instalar_tomcat_desde_tarball "$destino" ;;
    esac
}

# =============================================================================
# INSTALACION MANUAL DESDE TARBALL (sin P6 - para uso desde FTP)
# =============================================================================

instalar_apache_desde_tarball() {
    local tarball="$1"
    local version
    version=$(basename "$tarball" | grep -oP '\d+\.\d+\.\d+')
    local build_dir="/tmp/httpd-build"
    local install_dir="/opt/apache"

    info "Instalando Apache $version desde tarball..."

    # Dependencias
    dnf install -y gcc make pcre2-devel openssl-devel expat-devel \
        apr apr-devel apr-util apr-util-devel zlib-devel &>/dev/null

    mkdir -p "$build_dir"
    tar -xjf "$tarball" -C "$build_dir" --strip-components=1 2>/dev/null || \
    tar -xzf "$tarball" -C "$build_dir" --strip-components=1 2>/dev/null

    cd "$build_dir" || return 1
    ./configure --prefix="$install_dir" \
        --enable-so --enable-ssl --enable-rewrite \
        --with-mpm=prefork --with-pcre=/usr/bin/pcre2-config \
        &>/tmp/apache_configure.log

    make -j"$(nproc)" &>/tmp/apache_make.log
    make install &>/tmp/apache_install.log

    # Servicio systemd
    cat > /etc/systemd/system/httpd-custom.service <<EOF
[Unit]
Description=Apache HTTPD $version (Tarea 7)
After=network.target

[Service]
Type=forking
ExecStart=$install_dir/bin/apachectl start
ExecStop=$install_dir/bin/apachectl stop
ExecReload=$install_dir/bin/apachectl graceful
PIDFile=$install_dir/logs/httpd.pid

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now httpd-custom 2>/dev/null

    cd / && rm -rf "$build_dir"
    ok "Apache $version instalado en $install_dir"
}

instalar_nginx_desde_tarball() {
    local tarball="$1"
    local version
    version=$(basename "$tarball" | grep -oP '\d+\.\d+\.\d+')
    local build_dir="/tmp/nginx-build"
    local install_dir="/opt/nginx"

    info "Instalando Nginx $version desde tarball..."

    dnf install -y gcc make pcre2-devel openssl-devel zlib-devel &>/dev/null

    mkdir -p "$build_dir"
    tar -xzf "$tarball" -C "$build_dir" --strip-components=1

    cd "$build_dir" || return 1
    ./configure --prefix="$install_dir" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-pcre \
        &>/tmp/nginx_configure.log

    make -j"$(nproc)" &>/tmp/nginx_make.log
    make install &>/tmp/nginx_install.log

    cat > /etc/systemd/system/nginx-custom.service <<EOF
[Unit]
Description=Nginx $version (Tarea 7)
After=network.target

[Service]
Type=forking
ExecStart=$install_dir/sbin/nginx
ExecStop=$install_dir/sbin/nginx -s stop
ExecReload=$install_dir/sbin/nginx -s reload
PIDFile=$install_dir/logs/nginx.pid

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now nginx-custom 2>/dev/null

    cd / && rm -rf "$build_dir"
    ok "Nginx $version instalado en $install_dir"
}

instalar_tomcat_desde_tarball() {
    local tarball="$1"
    local version
    version=$(basename "$tarball" | grep -oP '\d+\.\d+\.\d+')
    local install_dir="/opt/tomcat-$version"

    info "Instalando Tomcat $version desde tarball..."

    dnf install -y java-21-openjdk &>/dev/null

    mkdir -p "$install_dir"
    tar -xzf "$tarball" -C "$install_dir" --strip-components=1

    # Usuario dedicado
    id tomcat &>/dev/null || useradd -r -d "$install_dir" -s /sbin/nologin tomcat
    chown -R tomcat:tomcat "$install_dir"
    chmod +x "$install_dir/bin"/*.sh

    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(which java)")")")

    cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat $version (Tarea 7)
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=$java_home"
Environment="CATALINA_HOME=$install_dir"
ExecStart=$install_dir/bin/startup.sh
ExecStop=$install_dir/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now tomcat 2>/dev/null

    ok "Tomcat $version instalado en $install_dir"
}

# =============================================================================
# FLUJO COMPLETO: INSTALAR + SSL
# =============================================================================

instalar_servicio_completo() {
    local servicio="$1"   # apache | nginx | tomcat

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}   INSTALACION: $(echo "$servicio" | tr '[:lower:]' '[:upper:]')${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"

    elegir_fuente

    if [ "$FUENTE_INSTALACION" = "1" ]; then
        instalar_desde_web "$servicio"
    else
        instalar_desde_ftp "$servicio"
    fi

    if [ $? -ne 0 ]; then
        err "Instalacion de $servicio fallida"
        return 1
    fi

    ok "$servicio instalado correctamente"

    # Preguntar SSL
    echo ""
    read -rp "  Activar SSL/TLS en $servicio? [S/n]: " activar_ssl
    if [[ ! "$activar_ssl" =~ ^[nN]$ ]]; then
        local puerto_https
        read -rp "  Puerto HTTPS (default: 443): " puerto_https
        puerto_https="${puerto_https:-443}"

        case "$servicio" in
            apache) ssl_apache 80 "$puerto_https" ;;
            nginx)  ssl_nginx  80 "$puerto_https" ;;
            tomcat) ssl_tomcat 8080 "$puerto_https" ;;
        esac
    fi
}