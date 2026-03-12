#!/bin/bash
# =============================================================================
# http_functions.sh — Funciones para despliegue de servidores HTTP
# Práctica 6 — Administración de Sistemas
# Distribución: Rocky Linux / RHEL / CentOS
# =============================================================================

# ─── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# =============================================================================
# UTILIDADES GENERALES
# =============================================================================

function log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
function log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
function log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Validar que una cadena no esté vacía y no tenga caracteres peligrosos
function validar_entrada() {
    local valor="$1"
    local nombre="$2"
    if [ -z "$valor" ]; then
        log_err "El campo '$nombre' no puede estar vacío."
        return 1
    fi
    if [[ "$valor" =~ [^a-zA-Z0-9._-] ]]; then
        log_err "El campo '$nombre' contiene caracteres no permitidos."
        return 1
    fi
    return 0
}

# Validar puerto: numérico, rango 1-65535, no reservado para otros servicios
function validar_puerto() {
    local puerto="$1"
    local puertos_reservados=(21 22 25 53 3306 5432 6379 27017)

    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        log_err "El puerto debe ser un número entero."
        return 1
    fi
    if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
        log_err "El puerto debe estar entre 1 y 65535."
        return 1
    fi
    for reservado in "${puertos_reservados[@]}"; do
        if [ "$puerto" -eq "$reservado" ]; then
            log_err "El puerto $puerto está reservado para otro servicio."
            return 1
        fi
    done
    # Verificar si el puerto está ocupado
    if ss -tuln 2>/dev/null | grep -q ":${puerto} "; then
        log_warn "El puerto $puerto ya está en uso por otro proceso."
        return 1
    fi
    return 0
}

# Configurar firewall para el puerto dado
function configurar_firewall_puerto() {
    local puerto="$1"
    local puertos_default=(80 8080 8888 8009)

    log_info "Configurando firewall para puerto $puerto..."
    sudo firewall-cmd --permanent --add-port=${puerto}/tcp > /dev/null 2>&1

    # Cerrar puertos HTTP por defecto que no se estén usando
    for p in "${puertos_default[@]}"; do
        if [ "$p" -ne "$puerto" ]; then
            if ! ss -tuln 2>/dev/null | grep -q ":${p} "; then
                sudo firewall-cmd --permanent --remove-port=${p}/tcp > /dev/null 2>&1
            fi
        fi
    done
    sudo firewall-cmd --reload > /dev/null 2>&1
    log_ok "Firewall configurado: puerto $puerto abierto."
}

# Crear usuario de sistema dedicado para un servicio
function crear_usuario_servicio() {
    local usuario="$1"
    local directorio="$2"

    if ! id "$usuario" &>/dev/null; then
        sudo useradd -r -s /sbin/nologin -d "$directorio" "$usuario"
        log_ok "Usuario de servicio '$usuario' creado."
    else
        log_info "Usuario de servicio '$usuario' ya existe."
    fi

    sudo mkdir -p "$directorio"
    sudo chown -R "$usuario":"$usuario" "$directorio"
    sudo chmod 750 "$directorio"
}

# =============================================================================
# APACHE HTTPD — Descarga desde sitio oficial
# =============================================================================

APACHE_INSTALL_DIR="/opt/apache"
APACHE_VERSIONES=()

function listar_versiones_apache() {
    echo ""
    log_info "Consultando versiones disponibles de Apache HTTPD en downloads.apache.org..."
    echo ""

    APACHE_VERSIONES=()

    # Obtener versiones 2.4.x disponibles en downloads.apache.org (solo las actuales)
    local pagina
    pagina=$(curl -s "https://downloads.apache.org/httpd/" 2>/dev/null)

    if [ -z "$pagina" ]; then
        log_warn "Sin conexión. Usando versiones conocidas."
        APACHE_VERSIONES=("2.4.62" "2.4.63" "2.4.63")
    else
        # Extraer SOLO versiones 2.4.x (descartar 2.2.x, 2.0.x)
        local versiones_24
        versiones_24=$(echo "$pagina" | grep -o 'httpd-2\.4\.[0-9]*\.tar\.gz' | \
                       grep -o '2\.4\.[0-9]*' | sort -V | uniq)

        local count
        count=$(echo "$versiones_24" | grep -c '^2' 2>/dev/null || echo 0)

        if [ "$count" -ge 2 ]; then
            # Estable anterior = penúltima versión 2.4.x
            local anterior
            anterior=$(echo "$versiones_24" | tail -2 | head -1)
            # Estable actual = última versión 2.4.x
            local estable
            estable=$(echo "$versiones_24" | tail -1)
            APACHE_VERSIONES=("$anterior" "$estable")
        elif [ "$count" -eq 1 ]; then
            local estable
            estable=$(echo "$versiones_24" | tail -1)
            # Calcular anterior restando 1 al patch
            local patch
            patch=$(echo "$estable" | cut -d. -f3)
            local anterior="2.4.$((patch - 1))"
            APACHE_VERSIONES=("$anterior" "$estable")
        else
            APACHE_VERSIONES=("2.4.62" "2.4.63")
        fi
    fi

    # Versión de desarrollo: buscar 2.4.x en archive que sea mayor a la estable actual
    # Como no hay rama 2.5 estable, usamos la última versión de archive como "latest"
    local latest
    latest=$(curl -s "https://archive.apache.org/dist/httpd/" 2>/dev/null | \
             grep -o 'httpd-2\.4\.[0-9]*\.tar\.gz' | \
             grep -o '2\.4\.[0-9]*' | sort -V | tail -1)

    # Solo agregar si es diferente a la estable actual
    local estable_actual="${APACHE_VERSIONES[1]}"
    if [ -n "$latest" ] && [ "$latest" != "$estable_actual" ]; then
        APACHE_VERSIONES+=("$latest")
    else
        # Usar la misma estable con etiqueta diferente o incrementar patch
        local patch
        patch=$(echo "$estable_actual" | cut -d. -f3)
        APACHE_VERSIONES+=("2.4.$((patch + 1))")
    fi

    echo -e "  ${CYAN}Versiones disponibles (Apache HTTPD):${NC}"
    echo ""
    local etiquetas=("Estable anterior" "Estable actual (LTS)" "Desarrollo (Latest)")
    local i=0
    for v in "${APACHE_VERSIONES[@]}"; do
        echo "    $((i+1)). $v — ${etiquetas[$i]:-Adicional}"
        ((i++))
    done
    echo ""
}

function instalar_apache() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   INSTALACIÓN DE APACHE HTTPD          ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # Instalar dependencias de compilación
    log_info "Instalando dependencias de compilación..."
    local deps=(gcc make pcre2 pcre2-devel openssl-devel expat-devel \
        libxml2-devel lua-devel brotli-devel zlib-devel \
        apr apr-devel apr-util apr-util-devel)
    local faltantes=()
    for dep in "${deps[@]}"; do
        if ! rpm -q "$dep" &>/dev/null; then
            faltantes+=("$dep")
        fi
    done
    if [ ${#faltantes[@]} -gt 0 ]; then
        log_info "Instalando: ${faltantes[*]}"
        sudo dnf install -y "${faltantes[@]}"
        if [ $? -ne 0 ]; then
            log_warn "Algunas dependencias no se pudieron instalar. Continuando..."
        fi
    fi
    log_ok "Dependencias verificadas."

    listar_versiones_apache

    local total=${#APACHE_VERSIONES[@]}
    local seleccion version_elegida

    while true; do
        read -p "Seleccione número de versión (1-$total): " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "$total" ]; then
            version_elegida="${APACHE_VERSIONES[$((seleccion-1))]}"
            break
        fi
        log_err "Selección inválida. Ingrese un número entre 1 y $total."
    done

    local puerto
    while true; do
        read -p "Puerto de escucha (ej. 80, 8080, 8888): " puerto
        if validar_puerto "$puerto"; then
            break
        fi
    done

    # Detener servicio anterior si existe
    sudo systemctl stop httpd-custom 2>/dev/null

    # Descargar
    local url="https://downloads.apache.org/httpd/httpd-${version_elegida}.tar.gz"
    local tmp_dir="/tmp/apache-build"
    sudo mkdir -p "$tmp_dir"

    log_info "Descargando Apache HTTPD $version_elegida..."
    sudo curl -sL "$url" -o "$tmp_dir/httpd.tar.gz"

    if [ ! -s "$tmp_dir/httpd.tar.gz" ]; then
        log_info "Intentando mirror de archivo..."
        url="https://archive.apache.org/dist/httpd/httpd-${version_elegida}.tar.gz"
        sudo curl -sL "$url" -o "$tmp_dir/httpd.tar.gz"
    fi

    if [ ! -s "$tmp_dir/httpd.tar.gz" ]; then
        log_err "No se pudo descargar Apache $version_elegida"
        return 1
    fi

    # Extraer y compilar
    log_info "Extrayendo y compilando Apache $version_elegida (esto puede tardar varios minutos)..."
    cd "$tmp_dir"
    sudo tar -xzf httpd.tar.gz
    cd "httpd-${version_elegida}"

    sudo ./configure \
        --prefix="$APACHE_INSTALL_DIR" \
        --enable-so \
        --enable-ssl \
        --enable-rewrite \
        --enable-headers \
        --with-mpm=prefork \
        --with-pcre=/usr/bin/pcre2-config \
        --with-apr=/usr \
        --with-apr-util=/usr \
        > /tmp/apache-configure.log 2>&1

    if [ $? -ne 0 ]; then
        log_err "Error en ./configure. Revisa /tmp/apache-configure.log"
        return 1
    fi

    sudo make -j$(nproc) > /tmp/apache-make.log 2>&1
    if [ $? -ne 0 ]; then
        log_err "Error en make. Revisa /tmp/apache-make.log"
        return 1
    fi

    sudo make install > /dev/null 2>&1
    sudo rm -rf "$tmp_dir"
    log_ok "Apache HTTPD $version_elegida compilado e instalado en $APACHE_INSTALL_DIR"

    # Configurar puerto
    sudo sed -i "s/^Listen .*/Listen $puerto/" "$APACHE_INSTALL_DIR/conf/httpd.conf"
    sudo sed -i "s/^#ServerName .*/ServerName localhost:$puerto/" "$APACHE_INSTALL_DIR/conf/httpd.conf"

    # Seguridad
    configurar_seguridad_apache_src

    # Crear usuario dedicado
    crear_usuario_servicio "apache-srv" "$APACHE_INSTALL_DIR/htdocs"
    sudo sed -i "s/^User .*/User apache-srv/" "$APACHE_INSTALL_DIR/conf/httpd.conf"
    sudo sed -i "s/^Group .*/Group apache-srv/" "$APACHE_INSTALL_DIR/conf/httpd.conf"

    # Crear index.html
    sudo tee "$APACHE_INSTALL_DIR/htdocs/index.html" > /dev/null <<EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Apache HTTPD - Administración de Sistemas</title></head>
<body style="font-family:Arial;text-align:center;margin-top:80px;background:#f0f4f8">
  <h1 style="color:#c0392b">Apache HTTPD</h1>
  <table style="margin:auto;border-collapse:collapse;width:400px">
    <tr style="background:#c0392b;color:white">
      <th style="padding:10px">Campo</th><th style="padding:10px">Valor</th>
    </tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Servidor</td>
        <td style="padding:8px;border:1px solid #ddd">Apache HTTPD</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Version</td>
        <td style="padding:8px;border:1px solid #ddd">$version_elegida</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Puerto</td>
        <td style="padding:8px;border:1px solid #ddd">$puerto</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Sistema</td>
        <td style="padding:8px;border:1px solid #ddd">Rocky Linux</td></tr>
  </table>
</body>
</html>
EOF

    # Crear servicio systemd
    sudo tee /etc/systemd/system/httpd-custom.service > /dev/null <<EOF2
[Unit]
Description=Apache HTTPD $version_elegida (compilado)
After=network.target

[Service]
Type=forking
User=root
ExecStart=$APACHE_INSTALL_DIR/bin/apachectl start
ExecStop=$APACHE_INSTALL_DIR/bin/apachectl stop
ExecReload=$APACHE_INSTALL_DIR/bin/apachectl graceful
PIDFile=$APACHE_INSTALL_DIR/logs/httpd.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF2

    # SELinux
    if command -v semanage &>/dev/null; then
        sudo semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null || \
        sudo semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
    fi

    configurar_firewall_puerto "$puerto"

    sudo systemctl daemon-reload
    sudo systemctl enable httpd-custom > /dev/null 2>&1
    sudo systemctl restart httpd-custom

    sleep 2
    if systemctl is-active httpd-custom --quiet; then
        log_ok "Apache HTTPD $version_elegida corriendo en puerto $puerto."
        echo ""
        echo -e "${GREEN}Verificación con curl:${NC}"
        curl -sI "http://localhost:$puerto" 2>/dev/null | head -6
    else
        log_err "Apache no pudo iniciarse."
        sudo journalctl -xeu httpd-custom --no-pager | tail -15
    fi
}

function configurar_seguridad_apache_src() {
    log_info "Configurando seguridad Apache (ocultando versión)..."
    local httpd_conf="$APACHE_INSTALL_DIR/conf/httpd.conf"

    # Agregar directivas de seguridad al final del httpd.conf
    sudo tee -a "$httpd_conf" > /dev/null <<'EOF'

# === Seguridad ===
ServerTokens Prod
ServerSignature Off

# Encabezados de seguridad (requiere mod_headers)
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always unset X-Powered-By
</IfModule>

# Rechazar métodos peligrosos
<Location "/">
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Location>
EOF
    log_ok "Seguridad Apache configurada."
}

function configurar_seguridad_apache() {
    configurar_seguridad_apache_src
}

function configurar_metodos_apache() {
    log_info "Métodos HTTP ya configurados en configurar_seguridad_apache_src."
}

# =============================================================================
# NGINX — Descarga desde sitio oficial
# =============================================================================

NGINX_INSTALL_DIR="/opt/nginx"
NGINX_VERSIONES=()

function listar_versiones_nginx() {
    echo ""
    log_info "Consultando versiones disponibles de Nginx en nginx.org..."
    echo ""

    NGINX_VERSIONES=()

    local pagina
    pagina=$(curl -s "https://nginx.org/en/download.html" 2>/dev/null)

    if [ -z "$pagina" ]; then
        log_warn "Sin conexión. Usando versiones conocidas."
        NGINX_VERSIONES=("1.26.3" "1.27.4" "1.28.0")
    else
        # Mainline (desarrollo)
        local mainline
        mainline=$(echo "$pagina" | grep -o 'nginx-[0-9]*\.[0-9]*\.[0-9]*\.tar\.gz' | \
                   grep -o '[0-9]*\.[0-9]*\.[0-9]*' | \
                   awk -F. '$2 % 2 == 1' | sort -V | tail -1)

        # Stable actual
        local stable
        stable=$(echo "$pagina" | grep -o 'nginx-[0-9]*\.[0-9]*\.[0-9]*\.tar\.gz' | \
                 grep -o '[0-9]*\.[0-9]*\.[0-9]*' | \
                 awk -F. '$2 % 2 == 0' | sort -V | tail -1)

        # Stable anterior (penúltima versión minor estable)
        local stable_prev
        stable_prev=$(echo "$pagina" | grep -o 'nginx-[0-9]*\.[0-9]*\.[0-9]*\.tar\.gz' | \
                      grep -o '[0-9]*\.[0-9]*\.[0-9]*' | \
                      awk -F. '$2 % 2 == 0' | sort -V | tail -2 | head -1)

        [ -n "$stable_prev" ] && NGINX_VERSIONES+=("$stable_prev")
        [ -n "$stable" ] && NGINX_VERSIONES+=("$stable")
        [ -n "$mainline" ] && NGINX_VERSIONES+=("$mainline")
    fi

    # Si no se obtuvieron 3 versiones, completar con conocidas
    while [ ${#NGINX_VERSIONES[@]} -lt 3 ]; do
        NGINX_VERSIONES+=("1.26.3")
    done

    echo -e "  ${CYAN}Versiones disponibles (Nginx):${NC}"
    echo ""
    local etiquetas=("Estable anterior" "Estable actual" "Desarrollo (Mainline)")
    local i=0
    for v in "${NGINX_VERSIONES[@]}"; do
        echo "    $((i+1)). $v — ${etiquetas[$i]:-Adicional}"
        ((i++))
    done
    echo ""
}

function instalar_nginx() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   INSTALACIÓN DE NGINX                 ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # Dependencias de compilación
    log_info "Instalando dependencias de compilación..."
    local deps=(gcc make pcre2 pcre2-devel openssl-devel zlib-devel)
    local faltantes=()
    for dep in "${deps[@]}"; do
        if ! rpm -q "$dep" &>/dev/null; then
            faltantes+=("$dep")
        fi
    done
    if [ ${#faltantes[@]} -gt 0 ]; then
        log_info "Instalando: ${faltantes[*]}"
        sudo dnf install -y "${faltantes[@]}"
        if [ $? -ne 0 ]; then
            log_warn "Algunas dependencias no se pudieron instalar. Continuando..."
        fi
    fi
    log_ok "Dependencias verificadas."

    listar_versiones_nginx

    local total=${#NGINX_VERSIONES[@]}
    local seleccion version_elegida

    while true; do
        read -p "Seleccione número de versión (1-$total): " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "$total" ]; then
            version_elegida="${NGINX_VERSIONES[$((seleccion-1))]}"
            break
        fi
        log_err "Selección inválida."
    done

    local puerto
    while true; do
        read -p "Puerto de escucha (ej. 80, 8080, 8888): " puerto
        if validar_puerto "$puerto"; then
            break
        fi
    done

    sudo systemctl stop nginx-custom 2>/dev/null

    # Descargar
    local url="https://nginx.org/download/nginx-${version_elegida}.tar.gz"
    local tmp_dir="/tmp/nginx-build"
    sudo mkdir -p "$tmp_dir"

    log_info "Descargando Nginx $version_elegida..."
    sudo curl -sL "$url" -o "$tmp_dir/nginx.tar.gz"

    if [ ! -s "$tmp_dir/nginx.tar.gz" ]; then
        log_err "No se pudo descargar Nginx $version_elegida"
        return 1
    fi

    log_info "Compilando Nginx $version_elegida (esto puede tardar unos minutos)..."
    cd "$tmp_dir"
    sudo tar -xzf nginx.tar.gz
    cd "nginx-${version_elegida}"

    sudo ./configure \
        --prefix="$NGINX_INSTALL_DIR" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-pcre \
        > /tmp/nginx-configure.log 2>&1

    if [ $? -ne 0 ]; then
        log_err "Error en ./configure. Revisa /tmp/nginx-configure.log"
        return 1
    fi

    sudo make -j$(nproc) > /tmp/nginx-make.log 2>&1
    if [ $? -ne 0 ]; then
        log_err "Error en make. Revisa /tmp/nginx-make.log"
        return 1
    fi

    sudo make install > /dev/null 2>&1
    sudo rm -rf "$tmp_dir"
    log_ok "Nginx $version_elegida compilado e instalado en $NGINX_INSTALL_DIR"

    # Crear usuario dedicado
    crear_usuario_servicio "nginx-srv" "$NGINX_INSTALL_DIR/html"

    configurar_nginx "$puerto" "$version_elegida"

    # SELinux
    if command -v semanage &>/dev/null; then
        sudo semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null || \
        sudo semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
    fi

    configurar_firewall_puerto "$puerto"

    # Servicio systemd
    sudo tee /etc/systemd/system/nginx-custom.service > /dev/null <<EOF
[Unit]
Description=Nginx $version_elegida (compilado)
After=network.target

[Service]
Type=forking
PIDFile=$NGINX_INSTALL_DIR/logs/nginx.pid
ExecStartPre=$NGINX_INSTALL_DIR/sbin/nginx -t
ExecStart=$NGINX_INSTALL_DIR/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable nginx-custom > /dev/null 2>&1
    sudo systemctl restart nginx-custom

    sleep 2
    if systemctl is-active nginx-custom --quiet; then
        log_ok "Nginx $version_elegida corriendo en puerto $puerto."
        echo ""
        echo -e "${GREEN}Verificación con curl:${NC}"
        curl -sI "http://localhost:$puerto" 2>/dev/null | head -6
    else
        log_err "Nginx no pudo iniciarse."
        sudo journalctl -xeu nginx-custom --no-pager | tail -15
    fi
}

function configurar_nginx() {
    local puerto="$1"
    local version="$2"

    log_info "Configurando Nginx en puerto $puerto..."

    sudo tee "$NGINX_INSTALL_DIR/conf/nginx.conf" > /dev/null <<EOF
user nginx-srv;
worker_processes auto;
error_log $NGINX_INSTALL_DIR/logs/error.log;
pid $NGINX_INSTALL_DIR/logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    server_tokens off;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    include $NGINX_INSTALL_DIR/conf/mime.types;
    default_type application/octet-stream;

    server {
        listen $puerto;
        server_name localhost;
        root $NGINX_INSTALL_DIR/html;
        index index.html;

        if (\$request_method !~ ^(GET|POST|HEAD|OPTIONS)$) {
            return 405;
        }

        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}
EOF

    sudo tee "$NGINX_INSTALL_DIR/html/index.html" > /dev/null <<EOF2
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Nginx - Administración de Sistemas</title></head>
<body style="font-family:Arial;text-align:center;margin-top:80px;background:#f0f8f0">
  <h1 style="color:#27ae60">Nginx</h1>
  <table style="margin:auto;border-collapse:collapse;width:400px">
    <tr style="background:#27ae60;color:white">
      <th style="padding:10px">Campo</th><th style="padding:10px">Valor</th>
    </tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Servidor</td>
        <td style="padding:8px;border:1px solid #ddd">Nginx</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Version</td>
        <td style="padding:8px;border:1px solid #ddd">$version</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Puerto</td>
        <td style="padding:8px;border:1px solid #ddd">$puerto</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Sistema</td>
        <td style="padding:8px;border:1px solid #ddd">Rocky Linux</td></tr>
  </table>
</body>
</html>
EOF2

    sudo chown -R nginx-srv:nginx-srv "$NGINX_INSTALL_DIR/html" 2>/dev/null
    log_ok "Nginx configurado."
}


# =============================================================================
# TOMCAT
# =============================================================================

function listar_versiones_tomcat() {
    echo ""
    log_info "Consultando versiones disponibles de Apache Tomcat..."
    echo ""

    # Tomcat no está en repositorios estándar de Rocky — se descarga de Apache
    # Listamos las versiones LTS y latest consultando la API de Apache
    echo -e "  ${CYAN}Versiones disponibles (Apache Tomcat):${NC}"
    echo ""

    local versiones_tomcat=()

    # Tomcat 9 (LTS)
    local latest9
    latest9=$(curl -s "https://downloads.apache.org/tomcat/tomcat-9/" 2>/dev/null | \
              grep -o 'v9\.[0-9]*\.[0-9]*' | sort -V | tail -1)
    [ -n "$latest9" ] && versiones_tomcat+=("$latest9 (Tomcat 9 - LTS)")

    # Tomcat 10 (stable)
    local latest10
    latest10=$(curl -s "https://downloads.apache.org/tomcat/tomcat-10/" 2>/dev/null | \
               grep -o 'v10\.[0-9]*\.[0-9]*' | sort -V | tail -1)
    [ -n "$latest10" ] && versiones_tomcat+=("$latest10 (Tomcat 10 - Stable)")

    # Tomcat 11 (latest/dev)
    local latest11
    latest11=$(curl -s "https://downloads.apache.org/tomcat/tomcat-11/" 2>/dev/null | \
               grep -o 'v11\.[0-9]*\.[0-9]*' | sort -V | tail -1)
    [ -n "$latest11" ] && versiones_tomcat+=("$latest11 (Tomcat 11 - Latest)")

    # Fallback si no hay conexión
    if [ ${#versiones_tomcat[@]} -eq 0 ]; then
        log_warn "No se pudo consultar versiones en línea. Usando versiones conocidas."
        versiones_tomcat=("v9.0.100 (Tomcat 9 - LTS)" "v10.1.39 (Tomcat 10 - Stable)" "v11.0.5 (Tomcat 11 - Latest)")
    fi

    local i=1
    for v in "${versiones_tomcat[@]}"; do
        echo "    $i. $v"
        ((i++))
    done
    echo ""

    # Exportar para uso en instalar_tomcat
    TOMCAT_VERSIONES=("${versiones_tomcat[@]}")
}

function instalar_tomcat() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   INSTALACIÓN DE APACHE TOMCAT         ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # Verificar Java
    if ! command -v java &>/dev/null; then
        log_info "Java no encontrado. Instalando OpenJDK 17..."
        sudo dnf install -y java-17-openjdk java-17-openjdk-devel > /dev/null 2>&1
        if ! command -v java &>/dev/null; then
            log_err "No se pudo instalar Java. Tomcat requiere Java."
            return 1
        fi
        log_ok "Java instalado: $(java -version 2>&1 | head -1)"
    else
        log_ok "Java encontrado: $(java -version 2>&1 | head -1)"
    fi

    listar_versiones_tomcat

    local total=${#TOMCAT_VERSIONES[@]}
    local seleccion version_str version_num major

    while true; do
        read -p "Seleccione número de versión (1-$total): " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "$total" ]; then
            break
        fi
        log_err "Selección inválida."
    done

    version_str=$(echo "${TOMCAT_VERSIONES[$((seleccion-1))]}" | awk '{print $1}' | tr -d 'v')
    major=$(echo "$version_str" | cut -d'.' -f1)

    local puerto
    while true; do
        read -p "Puerto de escucha HTTP (ej. 8080, 8888): " puerto
        if validar_puerto "$puerto"; then
            break
        fi
    done

    local puerto_shutdown
    while true; do
        read -p "Puerto de shutdown de Tomcat (ej. 8005, distinto al anterior): " puerto_shutdown
        if validar_puerto "$puerto_shutdown" && [ "$puerto_shutdown" -ne "$puerto" ]; then
            break
        fi
        log_err "Puerto inválido o igual al puerto HTTP."
    done

    # Crear usuario dedicado
    crear_usuario_servicio "tomcat" "/opt/tomcat"

    # Descargar e instalar
    log_info "Descargando Apache Tomcat $version_str..."
    local url="https://downloads.apache.org/tomcat/tomcat-${major}/v${version_str}/bin/apache-tomcat-${version_str}.tar.gz"
    local tmp_dir="/tmp/tomcat-install"
    sudo mkdir -p "$tmp_dir"

    sudo curl -sL "$url" -o "$tmp_dir/tomcat.tar.gz"

    if [ ! -s "$tmp_dir/tomcat.tar.gz" ]; then
        log_err "No se pudo descargar Tomcat $version_str desde $url"
        log_info "Intentando con mirror alternativo..."
        url="https://archive.apache.org/dist/tomcat/tomcat-${major}/v${version_str}/bin/apache-tomcat-${version_str}.tar.gz"
        sudo curl -sL "$url" -o "$tmp_dir/tomcat.tar.gz"
    fi

    if [ ! -s "$tmp_dir/tomcat.tar.gz" ]; then
        log_err "No se pudo descargar Tomcat. Verifique conexión a internet."
        return 1
    fi

    log_info "Extrayendo Tomcat..."
    sudo tar -xzf "$tmp_dir/tomcat.tar.gz" -C /opt/
    sudo mv /opt/apache-tomcat-${version_str}/* /opt/tomcat/ 2>/dev/null || \
    sudo rsync -a /opt/apache-tomcat-${version_str}/ /opt/tomcat/
    sudo rm -rf /opt/apache-tomcat-${version_str} "$tmp_dir"

    sudo chown -R tomcat:tomcat /opt/tomcat
    sudo chmod 750 /opt/tomcat
    sudo chmod +x /opt/tomcat/bin/*.sh

    log_ok "Tomcat $version_str extraído en /opt/tomcat"

    # Configurar puertos en server.xml
    configurar_tomcat_server_xml "$puerto" "$puerto_shutdown"

    # Crear página index personalizada
    sudo tee /opt/tomcat/webapps/ROOT/index.jsp > /dev/null <<EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Tomcat - Administración de Sistemas</title></head>
<body style="font-family:Arial;text-align:center;margin-top:80px;background:#f0f0ff">
  <h1 style="color:#e67e22">Apache Tomcat</h1>
  <table style="margin:auto;border-collapse:collapse;width:400px">
    <tr style="background:#e67e22;color:white">
      <th style="padding:10px">Campo</th><th style="padding:10px">Valor</th>
    </tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Servidor</td>
        <td style="padding:8px;border:1px solid #ddd">Apache Tomcat</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Version</td>
        <td style="padding:8px;border:1px solid #ddd">$version_str</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Puerto</td>
        <td style="padding:8px;border:1px solid #ddd">$puerto</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Sistema</td>
        <td style="padding:8px;border:1px solid #ddd">Rocky Linux</td></tr>
  </table>
</body>
</html>
EOF

    # Crear servicio systemd
    crear_servicio_systemd_tomcat

    # SELinux
    if command -v semanage &>/dev/null; then
        sudo semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null || \
        sudo semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
    fi

    configurar_firewall_puerto "$puerto"

    sudo systemctl daemon-reload
    sudo systemctl enable tomcat > /dev/null 2>&1
    sudo systemctl restart tomcat

    sleep 3
    if systemctl is-active tomcat --quiet; then
        log_ok "Tomcat corriendo en puerto $puerto."
        echo ""
        echo -e "${GREEN}Verificación con curl:${NC}"
        curl -sI "http://localhost:$puerto" 2>/dev/null | head -5
    else
        log_err "Tomcat no pudo iniciarse."
        sudo journalctl -xeu tomcat --no-pager | tail -15
    fi
}

function configurar_tomcat_server_xml() {
    local puerto_http="$1"
    local puerto_shutdown="$2"
    local server_xml="/opt/tomcat/conf/server.xml"

    log_info "Configurando server.xml (puertos HTTP=$puerto_http, shutdown=$puerto_shutdown)..."

    # Cambiar puerto shutdown
    sudo sed -i "s/port=\"8005\"/port=\"$puerto_shutdown\"/" "$server_xml"
    # Cambiar puerto HTTP
    sudo sed -i "s/port=\"8080\"/port=\"$puerto_http\"/" "$server_xml"
    # Ocultar versión del servidor (ServerInfo)
    sudo sed -i 's/redirectPort="8443"/redirectPort="8443" server="Apache"/' "$server_xml"

    # Configurar encabezados de seguridad en web.xml
    local web_xml="/opt/tomcat/conf/web.xml"
    if ! grep -q "X-Frame-Options" "$web_xml" 2>/dev/null; then
        sudo sed -i 's|</web-app>|  <!-- Security Headers -->\n  <filter>\n    <filter-name>httpHeaderSecurity</filter-name>\n    <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>\n    <init-param><param-name>antiClickJackingEnabled</param-name><param-value>true</param-value></init-param>\n    <init-param><param-name>antiClickJackingOption</param-name><param-value>SAMEORIGIN</param-value></init-param>\n    <init-param><param-name>xContentTypeOptionsEnabled</param-name><param-value>true</param-value></init-param>\n  </filter>\n  <filter-mapping>\n    <filter-name>httpHeaderSecurity</filter-name>\n    <url-pattern>/*</url-pattern>\n  </filter-mapping>\n</web-app>|' "$web_xml"
    fi

    log_ok "server.xml configurado."
}

function crear_servicio_systemd_tomcat() {
    local java_home
    java_home=$(dirname $(dirname $(readlink -f $(which java))))

    sudo tee /etc/systemd/system/tomcat.service > /dev/null <<EOF
[Unit]
Description=Apache Tomcat Web Application Server
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat

Environment="JAVA_HOME=$java_home"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    log_ok "Servicio systemd de Tomcat creado."
}

# =============================================================================
# GESTIÓN DE SERVICIOS
# =============================================================================

function ver_estado_servicios() {
    echo ""
    echo -e "${CYAN}=== ESTADO DE SERVICIOS HTTP ===${NC}"
    echo ""

    for servicio in httpd nginx tomcat; do
        if systemctl list-unit-files "$servicio.service" &>/dev/null; then
            local estado
            if systemctl is-active "$servicio" --quiet; then
                estado="${GREEN}● ACTIVO${NC}"
            else
                estado="${RED}● INACTIVO${NC}"
            fi
            local puerto=""
            case $servicio in
                httpd) puerto=$(grep "^Listen" /etc/httpd/conf/httpd.conf 2>/dev/null | awk '{print $2}') ;;
                nginx) puerto=$(grep "listen" /etc/nginx/nginx.conf 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';' | head -1) ;;
                tomcat) puerto=$(grep 'protocol="HTTP' /opt/tomcat/conf/server.xml 2>/dev/null | grep -o 'port="[0-9]*"' | head -1 | tr -d 'port="') ;;
            esac
            printf "  %-10s %b  Puerto: %s\n" "$servicio" "$estado" "${puerto:-N/A}"
        fi
    done
    echo ""
}

function cambiar_puerto_servicio() {
    echo ""
    echo -e "${CYAN}=== CAMBIAR PUERTO DE SERVICIO ===${NC}"
    echo ""
    echo "  1. Apache httpd"
    echo "  2. Nginx"
    echo "  3. Tomcat"
    echo ""
    read -p "Seleccione servicio (1-3): " opcion

    local nuevo_puerto
    while true; do
        read -p "Nuevo puerto: " nuevo_puerto
        if validar_puerto "$nuevo_puerto"; then
            break
        fi
    done

    case $opcion in
        1)
            sudo sed -i "s/^Listen .*/Listen $nuevo_puerto/" /etc/httpd/conf/httpd.conf
            sudo semanage port -a -t http_port_t -p tcp "$nuevo_puerto" 2>/dev/null
            configurar_firewall_puerto "$nuevo_puerto"
            sudo systemctl restart httpd
            log_ok "Apache reiniciado en puerto $nuevo_puerto"
            ;;
        2)
            sudo sed -i "s/listen [0-9]*/listen $nuevo_puerto/" /etc/nginx/nginx.conf
            sudo semanage port -a -t http_port_t -p tcp "$nuevo_puerto" 2>/dev/null
            configurar_firewall_puerto "$nuevo_puerto"
            sudo systemctl restart nginx
            log_ok "Nginx reiniciado en puerto $nuevo_puerto"
            ;;
        3)
            sudo sed -i "s/port=\"[0-9]*\" protocol=\"HTTP/port=\"$nuevo_puerto\" protocol=\"HTTP/" \
                /opt/tomcat/conf/server.xml
            sudo semanage port -a -t http_port_t -p tcp "$nuevo_puerto" 2>/dev/null
            configurar_firewall_puerto "$nuevo_puerto"
            sudo systemctl restart tomcat
            log_ok "Tomcat reiniciado en puerto $nuevo_puerto"
            ;;
        *)
            log_err "Opción inválida."
            ;;
    esac
}

function ver_logs_servicio() {
    echo ""
    echo "  1. Apache httpd"
    echo "  2. Nginx"
    echo "  3. Tomcat"
    read -p "Seleccione servicio (1-3): " opcion

    case $opcion in
        1) sudo journalctl -u httpd -n 30 --no-pager ;;
        2) sudo journalctl -u nginx -n 30 --no-pager ;;
        3) sudo journalctl -u tomcat -n 30 --no-pager ;;
        *) log_err "Opción inválida." ;;
    esac
}

function desinstalar_servicio() {
    echo ""
    echo "  1. Apache httpd"
    echo "  2. Nginx"
    echo "  3. Tomcat"
    read -p "Seleccione servicio a desinstalar (1-3): " opcion

    read -p "¿Está seguro? (s/n): " confirm
    [ "$confirm" != "s" ] && [ "$confirm" != "S" ] && return 0

    case $opcion in
        1)
            sudo systemctl stop httpd 2>/dev/null
            sudo systemctl disable httpd 2>/dev/null
            sudo dnf remove -y httpd > /dev/null 2>&1
            sudo rm -f /etc/httpd/conf.d/security.conf /etc/httpd/conf.d/metodos.conf
            log_ok "Apache httpd desinstalado."
            ;;
        2)
            sudo systemctl stop nginx 2>/dev/null
            sudo systemctl disable nginx 2>/dev/null
            sudo dnf remove -y nginx > /dev/null 2>&1
            log_ok "Nginx desinstalado."
            ;;
        3)
            sudo systemctl stop tomcat 2>/dev/null
            sudo systemctl disable tomcat 2>/dev/null
            sudo rm -rf /opt/tomcat /etc/systemd/system/tomcat.service
            sudo userdel tomcat 2>/dev/null
            sudo systemctl daemon-reload
            log_ok "Tomcat desinstalado."
            ;;
        *) log_err "Opción inválida." ;;
    esac
}