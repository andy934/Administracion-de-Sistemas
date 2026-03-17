#!/usr/bin/env bash
# =============================================================================
# func-install.sh - Orquestador de instalacion hibrida (WEB / FTP)
# Practica 7 - Administracion de Sistemas
# Reutiliza funciones de Practica 6 (http-func.sh)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P6_FUNC="$SCRIPT_DIR/../tarea6/http-func.sh"
INSTALL_TMP="/tmp/tarea7_install"
mkdir -p "$INSTALL_TMP"

# Bandera para evitar cargar P6 mas de una vez
_P6_CARGADO=0

# =============================================================================
# CARGAR FUNCIONES DE P6 (solo si existe)
# =============================================================================

_cargar_p6() {
    [ "$_P6_CARGADO" -eq 1 ] && return 0
    if [ -f "$P6_FUNC" ]; then
        # shellcheck source=/dev/null
        source "$P6_FUNC"
        _P6_CARGADO=1
        return 0
    else
        warn "No se encontro $P6_FUNC"
        warn "Para instalar desde WEB, los scripts de Practica 6 deben estar en:"
        warn "  $P6_FUNC"
        return 1
    fi
}

# =============================================================================
# VALIDACIONES DE DEPENDENCIAS CON RESOLUCION EN CONTEXTO
# =============================================================================

# Verifica si un servicio esta instalado; ofrece instalarlo si no
_validar_servicio() {
    local servicio="$1"    # apache | nginx | tomcat
    local binario fuente_check

    case "$servicio" in
        apache) binario="/opt/apache/bin/apachectl" ;;
        nginx)  binario="/opt/nginx/sbin/nginx"     ;;
        tomcat) binario=$(find /opt -name "catalina.sh" 2>/dev/null | head -1) ;;
    esac

    if [ -n "$binario" ] && [ -f "$binario" ]; then
        return 0   # ya instalado
    fi

    warn "$servicio no esta instalado"
    read -rp "  Instalar $servicio ahora? [S/n]: " r
    [[ "$r" =~ ^[nN]$ ]] && return 1

    instalar_servicio_completo "$servicio"
    return $?
}

# =============================================================================
# PREGUNTAR FUENTE DE INSTALACION
# =============================================================================

_elegir_fuente() {
    echo ""
    echo -e "${CYAN}  Fuente de instalacion:${NC}"
    echo "    1. WEB — desde repositorio oficial en internet"
    echo "    2. FTP — desde repositorio privado local"
    echo ""
    local fuente=""
    while [[ "$fuente" != "1" && "$fuente" != "2" ]]; do
        read -rp "  Seleccione fuente (1/2): " fuente
    done
    FUENTE_INSTALACION="$fuente"
}

# =============================================================================
# INSTALACION DESDE WEB (delega a P6)
# =============================================================================

_instalar_web() {
    local servicio="$1"

    _cargar_p6 || return 1

    info "Instalando $servicio desde WEB (Practica 6)..."
    case "$servicio" in
        apache)
            listar_versiones_apache
            instalar_apache
            ;;
        nginx)
            listar_versiones_nginx
            instalar_nginx
            ;;
        tomcat)
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
# INSTALACION DESDE FTP
# =============================================================================

_instalar_ftp() {
    local servicio="$1"

    # Validar que el repo este listo antes de intentar usarlo
    _validar_repo || return 1

    local svc_dir
    case "$servicio" in
        apache) svc_dir="Apache" ;;
        nginx)  svc_dir="Nginx"  ;;
        tomcat) svc_dir="Tomcat" ;;
        *)      err "Servicio desconocido: $servicio"; return 1 ;;
    esac

    # Navegar repo y seleccionar archivo
    seleccionar_desde_ftp "$svc_dir" || return 1

    # Descargar binario
    local destino="$INSTALL_TMP/$ARCHIVO_FTP_SELECCIONADO"
    descargar_ftp "$RUTA_FTP_SELECCIONADA" "$destino" || return 1

    # Verificar integridad SHA256
    echo ""
    verificar_hash "$destino" "${RUTA_FTP_SELECCIONADA}.sha256"
    local hash_ok=$?

    if [ "$hash_ok" -ne 0 ]; then
        echo ""
        read -rp "  Hash no coincide. Continuar de todas formas? [s/N]: " forzar
        [[ "$forzar" =~ ^[sS]$ ]] || { rm -f "$destino"; return 1; }
        warn "Continuando con archivo sin verificar integridad"
    fi

    # Instalar desde tarball local
    echo ""
    info "Instalando $servicio desde archivo local verificado..."
    case "$servicio" in
        apache) _instalar_apache_tarball "$destino" ;;
        nginx)  _instalar_nginx_tarball  "$destino" ;;
        tomcat) _instalar_tomcat_tarball "$destino" ;;
    esac
}

# =============================================================================
# COMPILACION DESDE TARBALL — APACHE
# =============================================================================

_instalar_apache_tarball() {
    local tarball="$1"
    local version
    version=$(basename "$tarball" | grep -oP '\d+\.\d+\.\d+')
    local build_dir="/tmp/httpd-build-$$"
    local install_dir="/opt/apache"

    info "Compilando Apache $version..."

    dnf install -y gcc make pcre2-devel openssl-devel expat-devel \
        apr apr-devel apr-util apr-util-devel zlib-devel &>/dev/null

    mkdir -p "$build_dir"
    tar -xjf "$tarball" -C "$build_dir" --strip-components=1 2>/dev/null || \
        tar -xzf "$tarball" -C "$build_dir" --strip-components=1 2>/dev/null

    cd "$build_dir" || return 1
    ./configure --prefix="$install_dir" \
        --enable-so --enable-ssl --enable-rewrite \
        --with-mpm=prefork \
        --with-pcre=/usr/bin/pcre2-config \
        > /tmp/apache_conf.log 2>&1

    make -j"$(nproc)" > /tmp/apache_make.log 2>&1
    make install      > /tmp/apache_inst.log 2>&1

    # Configuracion de seguridad basica
    cat >> "$install_dir/conf/httpd.conf" <<'EOF'

# Seguridad basica - Practica 7
ServerTokens Prod
ServerSignature Off
LoadModule headers_module modules/mod_headers.so
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
EOF

    # Pagina de inicio
    cat > "$install_dir/htdocs/index.html" <<EOF
<html><body style="font-family:Arial;text-align:center;margin-top:80px">
<h1>Apache HTTPD $version</h1>
<p>Puerto: configurado | Sistema: Rocky Linux | Instalado desde: FTP</p>
</body></html>
EOF

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

# =============================================================================
# COMPILACION DESDE TARBALL — NGINX
# =============================================================================

_instalar_nginx_tarball() {
    local tarball="$1"
    local version
    version=$(basename "$tarball" | grep -oP '\d+\.\d+\.\d+')
    local build_dir="/tmp/nginx-build-$$"
    local install_dir="/opt/nginx"

    info "Compilando Nginx $version..."

    dnf install -y gcc make pcre2-devel openssl-devel zlib-devel &>/dev/null

    mkdir -p "$build_dir"
    tar -xzf "$tarball" -C "$build_dir" --strip-components=1

    cd "$build_dir" || return 1
    ./configure --prefix="$install_dir" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-pcre \
        > /tmp/nginx_conf.log 2>&1

    make -j"$(nproc)" > /tmp/nginx_make.log 2>&1
    make install      > /tmp/nginx_inst.log 2>&1

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

# =============================================================================
# INSTALACION DESDE TARBALL — TOMCAT
# =============================================================================

_instalar_tomcat_tarball() {
    local tarball="$1"
    local version
    version=$(basename "$tarball" | grep -oP '\d+\.\d+\.\d+')
    local install_dir="/opt/tomcat-$version"

    info "Instalando Tomcat $version..."

    dnf install -y java-21-openjdk &>/dev/null

    mkdir -p "$install_dir"
    tar -xzf "$tarball" -C "$install_dir" --strip-components=1

    id tomcat &>/dev/null || \
        useradd -r -d "$install_dir" -s /sbin/nologin tomcat
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
    local servicio="$1"

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}   INSTALACION: $(echo "$servicio" | tr '[:lower:]' '[:upper:]')${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo ""

    _elegir_fuente

    if [ "$FUENTE_INSTALACION" = "1" ]; then
        _instalar_web "$servicio" || return 1
    else
        _instalar_ftp "$servicio" || return 1
    fi

    ok "$servicio instalado correctamente"

    # Preguntar SSL
    echo ""
    read -rp "  Activar SSL/TLS en $servicio ahora? [S/n]: " activar_ssl
    if [[ ! "$activar_ssl" =~ ^[nN]$ ]]; then
        _validar_cert || { warn "SSL omitido (sin certificado)"; return 0; }

        local puerto_https
        case "$servicio" in
            apache) read -rp "  Puerto HTTPS [443]: " puerto_https; puerto_https="${puerto_https:-443}" ;;
            nginx)  read -rp "  Puerto HTTPS [443]: " puerto_https; puerto_https="${puerto_https:-443}" ;;
            tomcat) read -rp "  Puerto HTTPS [8443]: " puerto_https; puerto_https="${puerto_https:-8443}" ;;
        esac

        case "$servicio" in
            apache) ssl_apache 80      "$puerto_https" ;;
            nginx)  ssl_nginx  80      "$puerto_https" ;;
            tomcat) ssl_tomcat 8080    "$puerto_https" ;;
        esac
    fi
}

# =============================================================================
# VER ESTADO DE TODOS LOS SERVICIOS
# =============================================================================

ver_estado_servicios() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}   ESTADO DE SERVICIOS                    ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo ""

    local servicios=("vsftpd:FTP" "httpd-custom:Apache" "nginx-custom:Nginx" "tomcat:Tomcat")
    for entry in "${servicios[@]}"; do
        local svc="${entry%%:*}" nombre="${entry##*:}"
        local st; st=$(systemctl is-active "$svc" 2>/dev/null)
        local col="${RED}"; [ "$st" = "active" ] && col="${GREEN}"
        printf "  %-10s %-20s %b%s%b\n" "$nombre" "($svc)" "$col" "$st" "$NC"
    done

    echo ""
    echo -e "${CYAN}  Puertos en escucha:${NC}"
    ss -tlnp 2>/dev/null \
        | grep -E ':21\b|:80\b|:443\b|:8080\b|:8443\b|:9[0-9]{3}\b' \
        | awk '{print "    " $4}' | sort -u
    echo ""

    echo -e "${CYAN}  Certificado SSL:${NC}"
    if cert_existe; then
        local exp
        exp=$(openssl x509 -noout -enddate -in "$CERT" 2>/dev/null | cut -d= -f2)
        ok "  Existe: $CERT"
        info "  Expira: $exp"
    else
        warn "  No generado aun"
    fi
    echo ""
}