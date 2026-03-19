#!/usr/bin/env bash
# =============================================================================
# func-ssl.sh - Generacion de certificados SSL/TLS y configuracion de servicios
# Practica 7 - Administracion de Sistemas
# Sistema: Rocky Linux 9
# =============================================================================

SSL_DIR="/etc/ssl/tarea7"
DOMAIN="reprobados.com"
CERT="$SSL_DIR/reprobados.crt"
KEY="$SSL_DIR/reprobados.key"
DAYS=365

# =============================================================================
# VALIDACION: CERTIFICADO EXISTE
# =============================================================================

cert_existe() {
    [ -f "$CERT" ] && [ -f "$KEY" ]
}

_validar_cert() {
    if cert_existe; then
        return 0
    fi
    warn "No existe certificado SSL en $SSL_DIR"
    read -rp "  Generar certificado ahora? [S/n]: " r
    [[ "$r" =~ ^[nN]$ ]] && return 1
    generar_certificado
    return $?
}

# =============================================================================
# GENERAR CERTIFICADO AUTOFIRMADO
# =============================================================================

generar_certificado() {
    info "Generando certificado SSL autofirmado para $DOMAIN..."

    command -v openssl &>/dev/null || dnf install -y openssl &>/dev/null

    mkdir -p "$SSL_DIR"
    chmod 755 "$SSL_DIR"

    if cert_existe; then
        warn "Certificado ya existe en $SSL_DIR"
        read -rp "  Regenerar? [s/N]: " regen
        [[ "$regen" =~ ^[sS]$ ]] || { ok "Usando certificado existente"; return 0; }
    fi

    openssl req -x509 -nodes -days "$DAYS" \
        -newkey rsa:2048 \
        -keyout "$KEY" \
        -out "$CERT" \
        -subj "/C=MX/ST=Sinaloa/L=Culiacan/O=ITCULIACAN/OU=Sistemas/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN},DNS:localhost,IP:127.0.0.1" \
        2>/dev/null

    if [ $? -ne 0 ]; then
        err "Fallo la generacion del certificado"
        return 1
    fi

    chmod 640 "$KEY"
    chmod 644 "$CERT"

    ok "Certificado generado exitosamente:"
    ok "  Cert : $CERT"
    ok "  Key  : $KEY"
    ok "  CN   : $DOMAIN  (valido $DAYS dias)"

    # Mostrar fingerprint para referencia
    local fp
    fp=$(openssl x509 -noout -fingerprint -sha256 -in "$CERT" 2>/dev/null \
        | cut -d= -f2)
    info "  SHA256: $fp"
    return 0
}

# =============================================================================
# SSL PARA APACHE HTTPD (/opt/apache)
# =============================================================================

ssl_apache() {
    local puerto_http="${1:-80}"
    local puerto_https="${2:-443}"
    local apache_dir="/opt/apache"

    # Validaciones previas
    _validar_cert || return 1

    if [ ! -f "$apache_dir/bin/apachectl" ]; then
        err "Apache no encontrado en $apache_dir"
        err "Instala Apache primero (Opcion 3 del menu)"
        return 1
    fi

    info "Configurando SSL en Apache HTTPD (HTTP:$puerto_http -> HTTPS:$puerto_https)..."

    local httpd_conf="$apache_dir/conf/httpd.conf"
    local extra_dir="$apache_dir/conf/extra"

    # Habilitar modulos necesarios
    sed -i \
        -e 's|#LoadModule ssl_module|LoadModule ssl_module|g' \
        -e 's|#LoadModule socache_shmcb_module|LoadModule socache_shmcb_module|g' \
        -e 's|#LoadModule rewrite_module|LoadModule rewrite_module|g' \
        "$httpd_conf"

    # Asegurar puerto HTTPS en Listen
    grep -q "^Listen $puerto_https" "$httpd_conf" || \
        echo "Listen $puerto_https" >> "$httpd_conf"

    # Incluir archivos SSL si no estan ya incluidos
    grep -q "httpd-ssl-tarea7.conf" "$httpd_conf" || \
        echo "Include conf/extra/httpd-ssl-tarea7.conf" >> "$httpd_conf"
    grep -q "httpd-redirect-tarea7.conf" "$httpd_conf" || \
        echo "Include conf/extra/httpd-redirect-tarea7.conf" >> "$httpd_conf"

    # VirtualHost HTTPS
    cat > "$extra_dir/httpd-ssl-tarea7.conf" <<EOF
# VirtualHost HTTPS - generado por Practica 7
<VirtualHost *:$puerto_https>
    ServerName  ${DOMAIN}
    ServerAlias www.${DOMAIN}

    SSLEngine             on
    SSLCertificateFile    $CERT
    SSLCertificateKeyFile $KEY
    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        HIGH:!aNULL:!MD5:!3DES
    SSLHonorCipherOrder   on

    DocumentRoot "$apache_dir/htdocs"
    DirectoryIndex index.html

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options            "SAMEORIGIN"
    Header always set X-Content-Type-Options     "nosniff"
    Header always set X-XSS-Protection           "1; mode=block"

    ErrorLog  "$apache_dir/logs/ssl_error.log"
    CustomLog "$apache_dir/logs/ssl_access.log" combined
</VirtualHost>
EOF

    # Redireccion HTTP -> HTTPS
    cat > "$extra_dir/httpd-redirect-tarea7.conf" <<EOF
# Redireccion HTTP -> HTTPS - generado por Practica 7
<VirtualHost *:$puerto_http>
    ServerName ${DOMAIN}
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
EOF

    # Verificar configuracion
    local test_out
    test_out=$("$apache_dir/bin/apachectl" configtest 2>&1)
    if echo "$test_out" | grep -q "Syntax OK"; then
        systemctl restart httpd-custom 2>/dev/null || \
            "$apache_dir/bin/apachectl" restart 2>/dev/null
        firewall-cmd --permanent --add-port=${puerto_https}/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        ok "Apache SSL habilitado en puerto $puerto_https"
        ok "  Redireccion activa: $puerto_http -> $puerto_https"
        return 0
    else
        err "Error en configuracion de Apache:"
        echo "$test_out" | tail -5
        return 1
    fi
}

# =============================================================================
# SSL PARA NGINX (/opt/nginx)
# =============================================================================

ssl_nginx() {
    local puerto_http="${1:-80}"
    local puerto_https="${2:-443}"
    local nginx_dir="/opt/nginx"

    _validar_cert || return 1

    if [ ! -f "$nginx_dir/sbin/nginx" ]; then
        err "Nginx no encontrado en $nginx_dir"
        err "Instala Nginx primero (Opcion 4 del menu)"
        return 1
    fi

    if ! "$nginx_dir/sbin/nginx" -V 2>&1 | grep -q "with-http_ssl_module"; then
        err "Nginx no fue compilado con --with-http_ssl_module"
        return 1
    fi

    info "Configurando SSL en Nginx (HTTP:$puerto_http -> HTTPS:$puerto_https)..."

    # Detectar puerto HTTP actual en nginx.conf (puede no ser 80)
    local puerto_http_actual
    puerto_http_actual=$(grep -E "^\s+listen\s+[0-9]+;" "$nginx_dir/conf/nginx.conf" 2>/dev/null         | grep -v "ssl" | grep -oP '\d+' | head -1)
    [ -n "$puerto_http_actual" ] && puerto_http="$puerto_http_actual"

    cat > "$nginx_dir/conf/nginx.conf" <<EOF
worker_processes auto;
error_log  $nginx_dir/logs/error.log warn;
pid        $nginx_dir/logs/nginx.pid;

events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    sendfile      on;
    keepalive_timeout 65;

    # Redireccion HTTP -> HTTPS
    server {
        listen      $puerto_http;
        server_name ${DOMAIN} www.${DOMAIN};
        return 301  https://\$host\$request_uri;
    }

    # HTTPS
    server {
        listen      $puerto_https ssl;
        server_name ${DOMAIN} www.${DOMAIN};

        ssl_certificate     $CERT;
        ssl_certificate_key $KEY;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options            "SAMEORIGIN"  always;
        add_header X-Content-Type-Options     "nosniff"     always;
        add_header X-XSS-Protection           "1; mode=block" always;

        root  $nginx_dir/html;
        index index.html;
        location / { try_files \$uri \$uri/ =404; }
    }
}
EOF

    if "$nginx_dir/sbin/nginx" -t 2>&1 | grep -q "successful"; then
        systemctl restart nginx-custom 2>/dev/null || \
            "$nginx_dir/sbin/nginx" -s reload 2>/dev/null
        firewall-cmd --permanent --add-port=${puerto_https}/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        ok "Nginx SSL habilitado en puerto $puerto_https"
        ok "  Redireccion activa: $puerto_http -> $puerto_https"
        return 0
    else
        err "Error en configuracion de Nginx:"
        "$nginx_dir/sbin/nginx" -t 2>&1 | tail -5
        return 1
    fi
}

# =============================================================================
# SSL PARA TOMCAT (/opt/tomcat-*)
# =============================================================================

ssl_tomcat() {
    local puerto_http="${1:-8080}"
    local puerto_https="${2:-8443}"

    _validar_cert || return 1

    local tomcat_dir
    tomcat_dir=$(find /opt -maxdepth 1 -name "tomcat*" -type d 2>/dev/null | \
        sort | tail -1)

    if [ -z "$tomcat_dir" ]; then
        err "Tomcat no encontrado en /opt"
        err "Instala Tomcat primero (Opcion 5 del menu)"
        return 1
    fi

    info "Configurando SSL en Tomcat ($tomcat_dir)..."
    info "  HTTP:$puerto_http -> HTTPS:$puerto_https"

    # Convertir PEM a PKCS12 para Java
    local p12="$SSL_DIR/reprobados.p12"
    local p12_pass="tarea7ssl"

    openssl pkcs12 -export \
        -in "$CERT" -inkey "$KEY" \
        -out "$p12" -passout "pass:$p12_pass" \
        -name reprobados -legacy 2>/dev/null || \
    openssl pkcs12 -export \
        -in "$CERT" -inkey "$KEY" \
        -out "$p12" -passout "pass:$p12_pass" \
        -name reprobados 2>/dev/null
    chmod 644 "$p12"
    ok "Certificado PKCS12 generado: $p12"

    local server_xml="$tomcat_dir/conf/server.xml"

    # Agregar conector HTTPS si no existe
    if ! grep -q "port=\"$puerto_https\"" "$server_xml"; then
        sed -i "/<\/Service>/i\\
    <Connector port=\"$puerto_https\"\\
               protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               maxThreads=\"150\" SSLEnabled=\"true\"\\
               scheme=\"https\" secure=\"true\"\\
               keystoreFile=\"$p12\" keystorePass=\"$p12_pass\"\\
               clientAuth=\"false\" sslProtocol=\"TLS\"/>" \
            "$server_xml"
        ok "Conector HTTPS agregado en puerto $puerto_https"
    else
        info "Conector HTTPS ya existe en puerto $puerto_https"
    fi

    # Agregar redirectPort al conector HTTP
    sed -i \
        "s|port=\"$puerto_http\" protocol=\"HTTP/1.1\"|port=\"$puerto_http\" protocol=\"HTTP/1.1\" redirectPort=\"$puerto_https\"|g" \
        "$server_xml" 2>/dev/null

    systemctl restart tomcat 2>/dev/null
    # Abrir puertos en firewall
    firewall-cmd --permanent --add-port=${puerto_https}/tcp &>/dev/null
    firewall-cmd --reload &>/dev/null
    ok "Tomcat SSL habilitado en puerto $puerto_https"
    return 0
}

# =============================================================================
# FTPS PARA VSFTPD
# =============================================================================

ssl_vsftpd() {
    _validar_cert || return 1

    if ! systemctl is-active vsftpd &>/dev/null; then
        err "vsftpd no esta activo"
        read -rp "  Iniciarlo ahora? [S/n]: " r
        [[ "$r" =~ ^[nN]$ ]] && return 1
        systemctl start vsftpd || { err "No se pudo iniciar vsftpd"; return 1; }
    fi

    info "Configurando FTPS (SSL/TLS) en vsftpd..."

    local vsftpd_conf="/etc/vsftpd/vsftpd.conf"

    # Limpiar configuracion SSL previa
    sed -i '/^ssl_enable\|^rsa_cert_file\|^rsa_private_key_file\|^force_local_data_ssl\|^force_local_logins_ssl\|^ssl_tlsv1\|^ssl_sslv2\|^ssl_sslv3\|^require_ssl_reuse\|^ssl_ciphers/d' \
        "$vsftpd_conf"

    cat >> "$vsftpd_conf" <<EOF

# FTPS - SSL/TLS (generado por Practica 7)
ssl_enable=YES
rsa_cert_file=$CERT
rsa_private_key_file=$KEY
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
EOF

    systemctl restart vsftpd
    if systemctl is-active vsftpd &>/dev/null; then
        # FTP ya debe estar en firewall, asegurar que este habilitado
        firewall-cmd --permanent --add-service=ftp &>/dev/null
        firewall-cmd --permanent --add-port=40000-40100/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        ok "FTPS habilitado en vsftpd"
        ok "  Canal de control: cifrado"
        ok "  Canal de datos  : cifrado"
        return 0
    else
        err "vsftpd no pudo reiniciarse con SSL"
        journalctl -u vsftpd -n 10 --no-pager 2>/dev/null
        return 1
    fi
}

# =============================================================================
# VERIFICACION INDIVIDUAL SSL
# =============================================================================

verificar_ssl() {
    local host="${1:-localhost}" puerto="${2:-443}" servicio="${3:-Servicio}"

    local resultado
    resultado=$(echo "" | timeout 5 openssl s_client \
        -connect "${host}:${puerto}" \
        -servername "$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -subject -dates 2>/dev/null)

    if [ -n "$resultado" ]; then
        ok "$servicio (${host}:${puerto}) — SSL OK"
        echo "$resultado" | sed 's/^/      /'
        return 0
    else
        err "$servicio (${host}:${puerto}) — SSL FALLO o no responde"
        return 1
    fi
}

verificar_ftps() {
    local host="${1:-localhost}"
    info "Verificando FTPS en $host:21..."

    local resultado
    resultado=$(curl -v --ssl-reqd \
        --cacert "$CERT" \
        -u "$REPO_USER:$REPO_PASS" \
        "ftp://${host}/" 2>&1)

    if echo "$resultado" | grep -qi "ssl connection\|tls connection\|SSL_connect"; then
        ok "vsftpd FTPS — SSL OK"
        return 0
    else
        err "vsftpd FTPS — No se confirmo SSL"
        return 1
    fi
}

# =============================================================================
# RESUMEN AUTOMATIZADO DE TODOS LOS SERVICIOS SSL
# =============================================================================

resumen_ssl() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}   VERIFICACION AUTOMATIZADA SSL/TLS      ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo ""

    local pass=0 fail=0

    _check() {
        local svc="$1" host="$2" port="$3"
        if verificar_ssl "$host" "$port" "$svc" 2>/dev/null; then
            pass=$((pass+1))
        else
            fail=$((fail+1))
        fi
        echo ""
    }

    # Leer puertos configurados dinamicamente
    local apache_https
    apache_https=$(grep "^Listen " /opt/apache/conf/httpd.conf 2>/dev/null \
        | awk '{print $2}' | grep -v "^80$" | grep -v "^90$" | head -1)
    [ -n "$apache_https" ] && _check "Apache HTTPD" "localhost" "$apache_https"

    local nginx_https
    nginx_https=$(grep -E "^\s+listen.*ssl" /opt/nginx/conf/nginx.conf 2>/dev/null \
        | grep -oP '\d+' | head -1)
    [ -n "$nginx_https" ] && _check "Nginx" "localhost" "$nginx_https"

    local tomcat_https
    tomcat_https=$(grep -oP 'port="\K\d+(?="[^>]*SSLEnabled="true")' \
        /opt/tomcat*/conf/server.xml 2>/dev/null | head -1)
    [ -z "$tomcat_https" ] && tomcat_https="8443"
    systemctl is-active tomcat &>/dev/null && _check "Tomcat" "localhost" "$tomcat_https"

    # FTPS
    if systemctl is-active vsftpd &>/dev/null; then
        if verificar_ftps "localhost" 2>/dev/null; then
            pass=$((pass+1))
        else
            fail=$((fail+1))
        fi
        echo ""
    fi

    echo -e "  ┌─────────────────────────────────┐"
    printf  "  │  OK: %b%-3s%b  |  FALLO: %b%-3s%b        │\n" \
        "${GREEN}" "$pass" "${NC}" "${RED}" "$fail" "${NC}"
    echo -e "  └─────────────────────────────────┘"
    echo ""
}