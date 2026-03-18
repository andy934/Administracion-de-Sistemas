#!/usr/bin/env bash
# =============================================================================
# func-install.sh - Orquestador de instalacion hibrida (WEB / FTP)
# Practica 7 - Administracion de Sistemas
# Sistema: Rocky Linux 9
# Completamente autonomo - no depende de P5 ni P6
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P6_FUNC="$SCRIPT_DIR/../tarea6/http-func.sh"
INSTALL_TMP="/tmp/tarea7_install"
mkdir -p "$INSTALL_TMP"
_P6_CARGADO=0

# =============================================================================
# CARGAR P6 SI EXISTE (opcional)
# =============================================================================

_cargar_p6() {
    [ "$_P6_CARGADO" -eq 1 ] && return 0
    if [ -f "$P6_FUNC" ]; then
        source "$P6_FUNC"
        _P6_CARGADO=1
        return 0
    fi
    return 1
}

# =============================================================================
# INSTALACION DE VSFTPD DESDE CERO
# =============================================================================

instalar_vsftpd() {
    info "Instalando vsftpd desde cero..."

    dnf install -y vsftpd &>/dev/null
    if [ $? -ne 0 ]; then
        err "No se pudo instalar vsftpd"
        return 1
    fi

    # Configuracion basica funcional
    cat > /etc/vsftpd/vsftpd.conf <<'EOF'
# vsftpd.conf - Configuracion basica Practica 7
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd/user_list
chroot_local_user=YES
allow_writeable_chroot=YES
user_config_dir=/etc/vsftpd/users
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
EOF

    mkdir -p /etc/vsftpd/users
    mkdir -p /srv/ftp
    [ -f /etc/vsftpd/user_list ] || touch /etc/vsftpd/user_list

    # Firewall
    firewall-cmd --permanent --add-service=ftp &>/dev/null
    firewall-cmd --permanent --add-port=40000-40100/tcp &>/dev/null
    firewall-cmd --reload &>/dev/null

    systemctl enable --now vsftpd
    if systemctl is-active vsftpd &>/dev/null; then
        ok "vsftpd instalado y activo"
        return 0
    else
        err "vsftpd no pudo iniciarse"
        journalctl -u vsftpd -n 5 --no-pager 2>/dev/null
        return 1
    fi
}

# =============================================================================
# VALIDAR/INSTALAR VSFTPD CON RESOLUCION EN CONTEXTO
# =============================================================================

_validar_vsftpd_completo() {
    systemctl is-active vsftpd &>/dev/null && return 0

    if rpm -q vsftpd &>/dev/null; then
        warn "vsftpd instalado pero inactivo"
        read -rp "  Iniciar vsftpd ahora? [S/n]: " r
        [[ "$r" =~ ^[nN]$ ]] && return 1
        systemctl start vsftpd
        systemctl is-active vsftpd &>/dev/null && return 0
        err "No se pudo iniciar vsftpd"
        return 1
    fi

    warn "vsftpd no esta instalado"
    read -rp "  Instalar vsftpd ahora? [S/n]: " r
    [[ "$r" =~ ^[nN]$ ]] && return 1
    instalar_vsftpd
    return $?
}

# =============================================================================
# PREREQUISITOS DEL SISTEMA
# =============================================================================

instalar_prerequisitos() {
    info "Verificando prerequisitos del sistema..."
    local pkgs=("curl" "wget" "openssl" "gcc" "make" "tar" "bzip2")
    local faltantes=()
    for pkg in "${pkgs[@]}"; do
        command -v "$pkg" &>/dev/null || faltantes+=("$pkg")
    done
    if [ ${#faltantes[@]} -gt 0 ]; then
        info "Instalando: ${faltantes[*]}"
        dnf install -y "${faltantes[@]}" &>/dev/null
    fi
    ok "Prerequisitos verificados"
}

# =============================================================================
# ELEGIR FUENTE DE INSTALACION
# =============================================================================

_elegir_fuente() {
    # Si P6 no existe solo FTP disponible
    if [ ! -f "$P6_FUNC" ]; then
        warn "Scripts de P6 no encontrados — usando FTP/descarga directa"
        FUENTE_INSTALACION="2"
        return
    fi

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
# INSTALACION DESDE WEB
# =============================================================================

_instalar_web() {
    local servicio="$1"

    if _cargar_p6; then
        info "Instalando $servicio desde WEB (via P6)..."
        case "$servicio" in
            apache) listar_versiones_apache; instalar_apache ;;
            nginx)  listar_versiones_nginx;  instalar_nginx  ;;
            tomcat) listar_versiones_tomcat; instalar_tomcat ;;
            *) err "Servicio desconocido: $servicio"; return 1 ;;
        esac
    else
        info "Instalando $servicio desde WEB (descarga directa)..."
        _instalar_web_directo "$servicio"
    fi
}

_instalar_web_directo() {
    local servicio="$1"
    local url dest

    case "$servicio" in
        apache)
            local ver
            ver=$(curl -s https://downloads.apache.org/httpd/ 2>/dev/null \
                | grep -oP 'httpd-2\.4\.\d+\.tar\.bz2' \
                | sort -t. -k3 -n | tail -1)
            [ -z "$ver" ] && { err "No se detecto version de Apache"; return 1; }
            dest="$INSTALL_TMP/$ver"
            info "Descargando $ver..."
            curl -fL --progress-bar -o "$dest" \
                "https://downloads.apache.org/httpd/$ver" 2>/dev/null || return 1
            _instalar_apache_tarball "$dest"
            ;;
        nginx)
            local ver
            ver=$(curl -s https://nginx.org/en/download.html 2>/dev/null \
                | grep -oP 'nginx-1\.\d*[02468]\.\d+\.tar\.gz' \
                | sort -t. -k2 -n -k3 -n | tail -1)
            [ -z "$ver" ] && { err "No se detecto version de Nginx"; return 1; }
            dest="$INSTALL_TMP/$ver"
            info "Descargando $ver..."
            curl -fL --progress-bar -o "$dest" \
                "https://nginx.org/download/$ver" 2>/dev/null || return 1
            _instalar_nginx_tarball "$dest"
            ;;
        tomcat)
            local tver tv tfile
            tver=$(curl -s https://downloads.apache.org/tomcat/tomcat-10/ 2>/dev/null \
                | grep -oP 'v10\.\d+\.\d+' | sort -t. -k2 -n -k3 -n | tail -1)
            [ -z "$tver" ] && { err "No se detecto version de Tomcat"; return 1; }
            tv="${tver#v}"
            tfile="apache-tomcat-${tv}.tar.gz"
            dest="$INSTALL_TMP/$tfile"
            info "Descargando $tfile..."
            curl -fL --progress-bar -o "$dest" \
                "https://downloads.apache.org/tomcat/tomcat-10/${tver}/bin/$tfile" \
                2>/dev/null || return 1
            _instalar_tomcat_tarball "$dest"
            ;;
        *) err "Servicio desconocido: $servicio"; return 1 ;;
    esac
}

# =============================================================================
# INSTALACION DESDE FTP
# =============================================================================

_instalar_ftp() {
    local servicio="$1"

    _validar_repo || return 1

    local svc_dir
    case "$servicio" in
        apache) svc_dir="Apache" ;;
        nginx)  svc_dir="Nginx"  ;;
        tomcat) svc_dir="Tomcat" ;;
        *) err "Servicio desconocido: $servicio"; return 1 ;;
    esac

    seleccionar_desde_ftp "$svc_dir" || return 1

    local destino="$INSTALL_TMP/$ARCHIVO_FTP_SELECCIONADO"
    descargar_ftp "$RUTA_FTP_SELECCIONADA" "$destino" || return 1

    echo ""
    verificar_hash "$destino" "${RUTA_FTP_SELECCIONADA}.sha256"
    if [ $? -ne 0 ]; then
        read -rp "  Hash no coincide. Continuar de todas formas? [s/N]: " forzar
        [[ "$forzar" =~ ^[sS]$ ]] || { rm -f "$destino"; return 1; }
        warn "Continuando sin verificacion de integridad"
    fi

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
    local extract_dir="/tmp/httpd-extract-$$"
    local build_dir="/tmp/httpd-build-$$"
    local install_dir="/opt/apache"

    info "Compilando Apache $version..."

    dnf install -y gcc make pcre2-devel openssl-devel expat-devel \
        zlib-devel libxml2-devel lua-devel &>/dev/null

    mkdir -p "$extract_dir"
    tar -xjf "$tarball" -C "$extract_dir" 2>/dev/null || \
        tar -xzf "$tarball" -C "$extract_dir" 2>/dev/null

    local src_dir
    src_dir=$(find "$extract_dir" -maxdepth 1 -type d | grep -v "^$extract_dir$" | head -1)
    if [ -z "$src_dir" ]; then
        err "No se pudo extraer el tarball de Apache"
        rm -rf "$extract_dir"; return 1
    fi

    mkdir -p "$build_dir"
    cp -a "$src_dir/." "$build_dir/"
    rm -rf "$extract_dir"
    cd "$build_dir" || return 1

    # APR incluido
    info "Descargando APR y APR-util..."
    local apr_ver apr_util_ver
    apr_ver=$(curl -s https://downloads.apache.org/apr/ 2>/dev/null \
        | grep -oP 'apr-[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2' | grep -v util \
        | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    apr_util_ver=$(curl -s https://downloads.apache.org/apr/ 2>/dev/null \
        | grep -oP 'apr-util-[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2' \
        | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    [ -z "$apr_ver" ]      && apr_ver="1.7.6"
    [ -z "$apr_util_ver" ] && apr_util_ver="1.6.3"

    mkdir -p "$build_dir/srclib"
    curl -fL -o /tmp/apr.tar.bz2 \
        "https://downloads.apache.org/apr/apr-${apr_ver}.tar.bz2" 2>/dev/null
    curl -fL -o /tmp/apr-util.tar.bz2 \
        "https://downloads.apache.org/apr/apr-util-${apr_util_ver}.tar.bz2" 2>/dev/null
    tar -xjf /tmp/apr.tar.bz2      -C "$build_dir/srclib" 2>/dev/null
    tar -xjf /tmp/apr-util.tar.bz2 -C "$build_dir/srclib" 2>/dev/null
    mv "$build_dir/srclib/apr-${apr_ver}"           "$build_dir/srclib/apr"      2>/dev/null || true
    mv "$build_dir/srclib/apr-util-${apr_util_ver}" "$build_dir/srclib/apr-util" 2>/dev/null || true

    ./configure --prefix="$install_dir" \
        --enable-so --enable-ssl --enable-rewrite \
        --with-mpm=prefork --with-included-apr \
        --with-pcre=/usr/bin/pcre2-config \
        > /tmp/apache_conf.log 2>&1

    if grep -q "error:" /tmp/apache_conf.log 2>/dev/null && \
       ! grep -q "config.status" /tmp/apache_conf.log 2>/dev/null; then
        err "Error en ./configure:"; grep "error:" /tmp/apache_conf.log | tail -3
        cd / && rm -rf "$build_dir" /tmp/apr*.tar.bz2; return 1
    fi

    make -j"$(nproc)" > /tmp/apache_make.log 2>&1 || {
        err "Error en make:"; tail -3 /tmp/apache_make.log
        cd / && rm -rf "$build_dir" /tmp/apr*.tar.bz2; return 1
    }

    make install > /tmp/apache_inst.log 2>&1 || {
        err "Error en make install:"; tail -3 /tmp/apache_inst.log
        cd / && rm -rf "$build_dir" /tmp/apr*.tar.bz2; return 1
    }

    rm -f /tmp/apr*.tar.bz2

    grep -q "ServerTokens Prod" "$install_dir/conf/httpd.conf" || \
    cat >> "$install_dir/conf/httpd.conf" <<'APACHEEOF'

# Seguridad basica - Practica 7
ServerTokens Prod
ServerSignature Off
LoadModule headers_module modules/mod_headers.so
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
APACHEEOF

    cat > "$install_dir/htdocs/index.html" <<HTMLEOF
<html><body style="font-family:Arial;text-align:center;margin-top:80px">
<h1>Apache HTTPD $version</h1>
<p>Sistema: Rocky Linux 9 | Practica 7</p>
</body></html>
HTMLEOF

    cat > /etc/systemd/system/httpd-custom.service <<SVCEOF
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
SVCEOF

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
    tar -xzf "$tarball" -C "$build_dir" --strip-components=1 2>/dev/null || {
        local ext_dir="/tmp/nginx-ext-$$"
        mkdir -p "$ext_dir"
        tar -xzf "$tarball" -C "$ext_dir" 2>/dev/null
        local src; src=$(find "$ext_dir" -maxdepth 1 -type d | grep -v "^$ext_dir$" | head -1)
        [ -n "$src" ] && cp -a "$src/." "$build_dir/"
        rm -rf "$ext_dir"
    }

    cd "$build_dir" || return 1
    ./configure --prefix="$install_dir" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-pcre \
        > /tmp/nginx_conf.log 2>&1

    make -j"$(nproc)" > /tmp/nginx_make.log 2>&1 || {
        err "Error compilando Nginx:"; tail -3 /tmp/nginx_make.log; return 1
    }
    make install > /tmp/nginx_inst.log 2>&1

    chmod 755 "$install_dir/logs" 2>/dev/null || true

    # Puerto libre
    local puerto_nginx=80
    if ss -tlnp 2>/dev/null | grep -q ':80\b'; then
        puerto_nginx=91
        warn "Puerto 80 ocupado — usando $puerto_nginx para Nginx"
    fi
    sed -i "s/listen\s*80\s*;/listen $puerto_nginx;/" \
        "$install_dir/conf/nginx.conf" 2>/dev/null || true

    cat > /etc/systemd/system/nginx-custom.service <<SVCEOF
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
SVCEOF

    systemctl daemon-reload
    systemctl enable --now nginx-custom 2>/dev/null
    cd / && rm -rf "$build_dir"
    ok "Nginx $version instalado en $install_dir (puerto HTTP: $puerto_nginx)"
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

    id tomcat &>/dev/null || useradd -r -d "$install_dir" -s /sbin/nologin tomcat
    chown -R tomcat:tomcat "$install_dir"
    chmod +x "$install_dir/bin"/*.sh

    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(which java)")")")

    # server.xml limpio con redirectPort listo para SSL
    cat > "$install_dir/conf/server.xml" <<'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />
  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>
  <Service name="Catalina">
    <Connector port="8080" protocol="HTTP/1.1"
               connectionTimeout="20000"
               redirectPort="8443"
               maxParameterCount="1000" />
    <Engine name="Catalina" defaultHost="localhost">
      <Realm className="org.apache.catalina.realm.LockOutRealm">
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
               resourceName="UserDatabase"/>
      </Realm>
      <Host name="localhost" appBase="webapps"
            unpackWARs="true" autoDeploy="true">
        <Valve className="org.apache.catalina.valves.AccessLogValve"
               directory="logs" prefix="localhost_access_log"
               suffix=".txt" pattern="%h %l %u %t &quot;%r&quot; %s %b" />
      </Host>
    </Engine>
  </Service>
</Server>
XMLEOF

    chown tomcat:tomcat "$install_dir/conf/server.xml"

    cat > /etc/systemd/system/tomcat.service <<SVCEOF
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
SVCEOF

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

        local puerto_http puerto_https
        case "$servicio" in
            apache)
                puerto_http=$(grep "^Listen " /opt/apache/conf/httpd.conf 2>/dev/null \
                    | awk '{print $2}' | head -1)
                puerto_http="${puerto_http:-80}"
                read -rp "  Puerto HTTPS [443]: " puerto_https
                puerto_https="${puerto_https:-443}"
                ssl_apache "$puerto_http" "$puerto_https"
                ;;
            nginx)
                puerto_http=$(grep -E "^\s+listen\s+[0-9]+\s*;" \
                    /opt/nginx/conf/nginx.conf 2>/dev/null \
                    | grep -v ssl | grep -oP '\d+' | head -1)
                puerto_http="${puerto_http:-80}"
                read -rp "  Puerto HTTPS [444]: " puerto_https
                puerto_https="${puerto_https:-444}"
                ssl_nginx "$puerto_http" "$puerto_https"
                ;;
            tomcat)
                read -rp "  Puerto HTTPS [8443]: " puerto_https
                puerto_https="${puerto_https:-8443}"
                ssl_tomcat 8080 "$puerto_https"
                ;;
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
        | grep -E ':21\b|:80\b|:91\b|:443\b|:444\b|:8080\b|:8443\b' \
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