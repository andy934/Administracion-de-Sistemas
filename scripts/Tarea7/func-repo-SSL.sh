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
# GENERAR CERTIFICADO AUTOFIRMADO
# =============================================================================

generar_certificado() {
    info "Generando certificado SSL autofirmado para $DOMAIN..."

    if ! command -v openssl &>/dev/null; then
        info "Instalando openssl..."
        dnf install -y openssl &>/dev/null
    fi

    mkdir -p "$SSL_DIR"
    chmod 700 "$SSL_DIR"

    if [ -f "$CERT" ] && [ -f "$KEY" ]; then
        warn "Certificado ya existe en $SSL_DIR"
        read -rp "  Regenerar? [s/N]: " regen
        [[ "$regen" =~ ^[sS]$ ]] || return 0
    fi

    openssl req -x509 -nodes -days "$DAYS" \
        -newkey rsa:2048 \
        -keyout "$KEY" \
        -out "$CERT" \
        -subj "/C=MX/ST=Sinaloa/L=CuliACan/O=ITCULIACAN/OU=Sistemas/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN},DNS:localhost,IP:127.0.0.1" \
        2>/dev/null

    chmod 600 "$KEY"
    chmod 644 "$CERT"

    ok "Certificado generado:"
    ok "  Cert : $CERT"
    ok "  Key  : $KEY"
    ok "  CN   : $DOMAIN  (valido $DAYS dias)"
}

# =============================================================================
# SSL PARA APACHE HTTPD (compilado en /opt/apache)
# =============================================================================

ssl_apache() {
    local puerto_http="${1:-80}"
    local puerto_https="${2:-443}"
    local apache_dir="/opt/apache"
    local conf_dir="$apache_dir/conf"
    local extra_dir="$conf_dir/extra"

    info "Configurando SSL en Apache HTTPD (puerto $puerto_https)..."

    if [ ! -f "$apache_dir/bin/apachectl" ]; then
        err "Apache no encontrado en $apache_dir"
        return 1
    fi

    # Habilitar mod_ssl en httpd.conf
    local httpd_conf="$conf_dir/httpd.conf"
    sed -i 's|#LoadModule ssl_module|LoadModule ssl_module|g' "$httpd_conf"
    sed -i 's|#LoadModule socache_shmcb_module|LoadModule socache_shmcb_module|g' "$httpd_conf"

    # Incluir archivo SSL si no esta incluido
    if ! grep -q "httpd-ssl.conf" "$httpd_conf"; then
        echo "" >> "$httpd_conf"
        echo "Include conf/extra/httpd-ssl-tarea7.conf" >> "$httpd_conf"
    fi

    # Incluir redireccion HTTP->HTTPS
    if ! grep -q "httpd-redirect.conf" "$httpd_conf"; then
        echo "Include conf/extra/httpd-redirect.conf" >> "$httpd_conf"
    fi

    # Asegurar que escuche en puerto HTTPS
    if ! grep -q "^Listen $puerto_https" "$httpd_conf"; then
        echo "Listen $puerto_https" >> "$httpd_conf"
    fi

    # Generar VirtualHost HTTPS
    cat > "$extra_dir/httpd-ssl-tarea7.conf" <<EOF
# SSL VirtualHost - generado por Practica 7
<VirtualHost *:$puerto_https>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    SSLEngine on
    SSLCertificateFile    $CERT
    SSLCertificateKeyFile $KEY

    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        HIGH:!aNULL:!MD5:!3DES
    SSLHonorCipherOrder   on

    DocumentRoot "$apache_dir/htdocs"
    DirectoryIndex index.html

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"

    ErrorLog  "$apache_dir/logs/ssl_error.log"
    CustomLog "$apache_dir/logs/ssl_access.log" combined
</VirtualHost>
EOF

    # Redireccion HTTP -> HTTPS
    cat > "$extra_dir/httpd-redirect.conf" <<EOF
# Redireccion HTTP -> HTTPS - generado por Practica 7
<VirtualHost *:$puerto_http>
    ServerName ${DOMAIN}
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>
EOF

    # Asegurar mod_rewrite activo
    sed -i 's|#LoadModule rewrite_module|LoadModule rewrite_module|g' "$httpd_conf"

    # Verificar y reiniciar
    if "$apache_dir/bin/apachectl" configtest 2>/dev/null | grep -q "Syntax OK" || \
       "$apache_dir/bin/apachectl" configtest 2>&1 | grep -q "Syntax OK"; then
        systemctl restart httpd-custom 2>/dev/null || \
            "$apache_dir/bin/apachectl" restart 2>/dev/null
        ok "Apache SSL habilitado en puerto $puerto_https"
        ok "  Redireccion $puerto_http -> $puerto_https activa"
    else
        err "Error en configuracion de Apache SSL:"
        "$apache_dir/bin/apachectl" configtest 2>&1 | tail -5
        return 1
    fi
}

# =============================================================================
# SSL PARA NGINX (compilado en /opt/nginx)
# =============================================================================

ssl_nginx() {
    local puerto_http="${1:-80}"
    local puerto_https="${2:-443}"
    local nginx_dir="/opt/nginx"
    local conf="$nginx_dir/conf/nginx.conf"

    info "Configurando SSL en Nginx (puerto $puerto_https)..."

    if [ ! -f "$nginx_dir/sbin/nginx" ]; then
        err "Nginx no encontrado en $nginx_dir"
        return 1
    fi

    # Verificar que nginx fue compilado con ssl
    if ! "$nginx_dir/sbin/nginx" -V 2>&1 | grep -q "with-http_ssl_module"; then
        err "Nginx no fue compilado con --with-http_ssl_module"
        return 1
    fi

    cat > "$conf" <<EOF
worker_processes auto;
error_log  $nginx_dir/logs/error.log warn;
pid        $nginx_dir/logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;

    sendfile on;
    keepalive_timeout 65;

    # Redireccion HTTP -> HTTPS
    server {
        listen $puerto_http;
        server_name ${DOMAIN} www.${DOMAIN};
        return 301 https://\$host\$request_uri;
    }

    # HTTPS
    server {
        listen $puerto_https ssl;
        server_name ${DOMAIN} www.${DOMAIN};

        ssl_certificate     $CERT;
        ssl_certificate_key $KEY;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        root  $nginx_dir/html;
        index index.html;

        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}
EOF

    # Verificar y reiniciar
    if "$nginx_dir/sbin/nginx" -t 2>&1 | grep -q "successful"; then
        systemctl restart nginx-custom 2>/dev/null || \
            "$nginx_dir/sbin/nginx" -s reload 2>/dev/null
        ok "Nginx SSL habilitado en puerto $puerto_https"
        ok "  Redireccion $puerto_http -> $puerto_https activa"
    else
        err "Error en configuracion de Nginx SSL:"
        "$nginx_dir/sbin/nginx" -t 2>&1 | tail -5
        return 1
    fi
}

# =============================================================================
# SSL PARA TOMCAT (HTTPS connector)
# =============================================================================

ssl_tomcat() {
    local puerto_http="${1:-8080}"
    local puerto_https="${2:-8443}"

    info "Configurando SSL en Apache Tomcat (puerto $puerto_https)..."

    # Buscar instalacion de Tomcat activa
    local tomcat_dir
    tomcat_dir=$(find /opt -maxdepth 1 -name "tomcat*" -type d 2>/dev/null | head -1)
    if [ -z "$tomcat_dir" ]; then
        err "Tomcat no encontrado en /opt"
        return 1
    fi

    local server_xml="$tomcat_dir/conf/server.xml"

    # Convertir certificado PEM a PKCS12 (Tomcat lo requiere)
    local p12="$SSL_DIR/reprobados.p12"
    local p12_pass="tarea7ssl"
    openssl pkcs12 -export \
        -in "$CERT" -inkey "$KEY" \
        -out "$p12" -passout "pass:$p12_pass" \
        -name reprobados 2>/dev/null
    ok "Certificado PKCS12 generado: $p12"

    # Agregar conector HTTPS si no existe
    if ! grep -q "port=\"$puerto_https\"" "$server_xml"; then
        sed -i "/<\/Service>/i\\
    <Connector port=\"$puerto_https\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               maxThreads=\"150\" SSLEnabled=\"true\"\\
               scheme=\"https\" secure=\"true\"\\
               keystoreFile=\"$p12\"\\
               keystorePass=\"$p12_pass\"\\
               clientAuth=\"false\" sslProtocol=\"TLS\"/>
" "$server_xml"
        ok "Conector HTTPS agregado en puerto $puerto_https"
    else
        info "Conector HTTPS ya existe en puerto $puerto_https"
    fi

    # Agregar redireccion en conector HTTP (redirectPort)
    sed -i "s|port=\"$puerto_http\" protocol=\"HTTP/1.1\"|port=\"$puerto_http\" protocol=\"HTTP/1.1\" redirectPort=\"$puerto_https\"|g" \
        "$server_xml" 2>/dev/null

    systemctl restart tomcat 2>/dev/null
    ok "Tomcat SSL habilitado en puerto $puerto_https"
}

# =============================================================================
# SSL/FTPS PARA VSFTPD
# =============================================================================

ssl_vsftpd() {
    info "Configurando FTPS (SSL/TLS) en vsftpd..."

    local vsftpd_conf="/etc/vsftpd/vsftpd.conf"

    if [ ! -f "$vsftpd_conf" ]; then
        err "vsftpd.conf no encontrado"
        return 1
    fi

    # Eliminar configuracion SSL previa si existe
    sed -i '/^ssl_enable\|^rsa_cert_file\|^rsa_private_key_file\|^force_local_data_ssl\|^force_local_logins_ssl\|^ssl_tlsv1\|^ssl_sslv2\|^ssl_sslv3\|^require_ssl_reuse\|^ssl_ciphers/d' "$vsftpd_conf"

    # Agregar configuracion FTPS
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
        ok "FTPS habilitado en vsftpd"
        ok "  Canal de control: cifrado"
        ok "  Canal de datos  : cifrado"
    else
        err "vsftpd no pudo reiniciarse con SSL"
        journalctl -u vsftpd -n 10 --no-pager 2>/dev/null
        return 1
    fi
}

# =============================================================================
# VERIFICACION SSL AUTOMATIZADA
# =============================================================================

verificar_ssl() {
    # $1 = host, $2 = puerto, $3 = nombre del servicio
    local host="${1:-localhost}"
    local puerto="${2:-443}"
    local servicio="${3:-Servicio}"

    local resultado
    resultado=$(echo "" | openssl s_client \
        -connect "${host}:${puerto}" \
        -servername "$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -subject -dates -fingerprint 2>/dev/null)

    if [ -n "$resultado" ]; then
        ok "$servicio (${host}:${puerto}) — SSL OK"
        echo "$resultado" | sed 's/^/      /'
        return 0
    else
        err "$servicio (${host}:${puerto}) — SSL FALLO"
        return 1
    fi
}

verificar_ftps() {
    local host="${1:-localhost}"
    local puerto="${2:-21}"

    local resultado
    resultado=$(curl -v --ssl-reqd \
        --cacert "$CERT" \
        -u "anonymous:" \
        "ftp://${host}/" 2>&1 | grep -E "SSL|TLS|Connected|certificate")

    if echo "$resultado" | grep -qi "ssl\|tls"; then
        ok "vsftpd FTPS (${host}:${puerto}) — SSL OK"
        echo "$resultado" | head -5 | sed 's/^/      /'
        return 0
    else
        err "vsftpd FTPS — No se pudo verificar SSL"
        return 1
    fi
}

# =============================================================================
# RESUMEN DE VERIFICACION DE TODOS LOS SERVICIOS
# =============================================================================

resumen_ssl() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}   RESUMEN DE VERIFICACION SSL/TLS        ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo ""

    local pass=0
    local fail=0

    # Detectar puertos HTTPS activos por servicio
    _check_ssl() {
        local svc="$1" host="$2" port="$3"
        if verificar_ssl "$host" "$port" "$svc" 2>/dev/null; then
            pass=$((pass+1))
        else
            fail=$((fail+1))
        fi
    }

    # Apache
    local apache_https
    apache_https=$(grep -r "^Listen" /opt/apache/conf/httpd.conf 2>/dev/null \
        | grep -v "^#" | awk '{print $2}' | grep -v "^80$" | head -1)
    [ -n "$apache_https" ] && _check_ssl "Apache HTTPD" "localhost" "$apache_https"

    # Nginx
    local nginx_https
    nginx_https=$(grep -E "listen.*ssl" /opt/nginx/conf/nginx.conf 2>/dev/null \
        | grep -oP '\d+' | head -1)
    [ -n "$nginx_https" ] && _check_ssl "Nginx" "localhost" "$nginx_https"

    # Tomcat
    local tomcat_https
    tomcat_https=$(grep -oP 'port="\K[^"]+(?="[^>]*SSLEnabled="true")' \
        /opt/tomcat*/conf/server.xml 2>/dev/null | head -1)
    [ -z "$tomcat_https" ] && tomcat_https="8443"
    _check_ssl "Tomcat" "localhost" "$tomcat_https"

    # FTPS
    if systemctl is-active vsftpd &>/dev/null; then
        if verificar_ftps "localhost" "21" 2>/dev/null; then
            pass=$((pass+1))
        else
            fail=$((fail+1))
        fi
    fi

    echo ""
    echo -e "  Resultado: ${GREEN}$pass OK${NC}  ${RED}$fail FALLO${NC}"
    echo ""
}