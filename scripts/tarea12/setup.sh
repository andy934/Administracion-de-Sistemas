#!/bin/bash
# =============================================================
# setup.sh - Configuracion inicial del servidor de correo
# Tarea 12 - reprobados.com
# =============================================================

set -e

DOMINIO="reprobados.com"
HOSTNAME_MAIL="mail.reprobados.com"
IP_SERVIDOR="192.168.116.128"
DIR_TAREA="$(cd "$(dirname "$0")" && pwd)"
DIR_CERTS="$DIR_TAREA/certs"
DIR_CONFIG="$DIR_TAREA/config"

# Colores
OK="\e[32m[OK]\e[0m"
INFO="\e[36m[INFO]\e[0m"
WARN="\e[33m[WARN]\e[0m"
ERR="\e[31m[ERROR]\e[0m"

echo ""
echo "  +============================================+"
echo "  |   SETUP SERVIDOR DE CORREO - TAREA 12     |"
echo "  |   Dominio: $DOMINIO                  |"
echo "  +============================================+"
echo ""

# =============================================================
# PASO 1: Verificar dependencias
# =============================================================
echo -e "$INFO Verificando dependencias..."

for cmd in docker openssl; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "$ERR '$cmd' no esta instalado."
        exit 1
    fi
done

if ! docker compose version &>/dev/null; then
    echo -e "$ERR 'docker compose' no disponible."
    exit 1
fi

echo -e "$OK Dependencias verificadas."

# =============================================================
# PASO 2: Crear estructura de directorios
# =============================================================
echo -e "$INFO Creando estructura de directorios..."

mkdir -p "$DIR_CERTS"
mkdir -p "$DIR_CONFIG/postfix"
mkdir -p "$DIR_CONFIG/dovecot"
mkdir -p "$DIR_CONFIG/rspamd"
mkdir -p "$DIR_TAREA/backups"

echo -e "$OK Directorios creados."

# =============================================================
# PASO 3: Generar certificados SSL autofirmados
# =============================================================
echo -e "$INFO Generando certificados SSL para $HOSTNAME_MAIL..."

if [ ! -f "$DIR_CERTS/fullchain.pem" ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$DIR_CERTS/privkey.pem" \
        -out    "$DIR_CERTS/fullchain.pem" \
        -subj "/C=MX/ST=Sinaloa/L=Los_Mochis/O=Reprobados/CN=$HOSTNAME_MAIL" \
        -addext "subjectAltName=IP:$IP_SERVIDOR,DNS:$HOSTNAME_MAIL,DNS:$DOMINIO"

    chmod 600 "$DIR_CERTS/privkey.pem"
    chmod 644 "$DIR_CERTS/fullchain.pem"
    echo -e "$OK Certificados generados en $DIR_CERTS"
else
    echo -e "$OK Certificados ya existen, omitiendo."
fi

# =============================================================
# PASO 4: Configurar DNS local (/etc/hosts)
# =============================================================
echo -e "$INFO Configurando DNS local en /etc/hosts..."

if ! grep -q "$HOSTNAME_MAIL" /etc/hosts; then
    echo "$IP_SERVIDOR  $HOSTNAME_MAIL $DOMINIO" >> /etc/hosts
    echo -e "$OK Registro DNS local agregado: $IP_SERVIDOR -> $HOSTNAME_MAIL"
else
    echo -e "$OK DNS local ya configurado."
fi

# =============================================================
# PASO 5: Levantar el contenedor
# =============================================================
echo -e "$INFO Levantando el contenedor mailserver..."
cd "$DIR_TAREA"
docker compose up -d

echo -e "$INFO Esperando que el contenedor inicie (30s)..."
sleep 30

# Verificar que esta corriendo
if ! docker ps | grep -q mailserver; then
    echo -e "$ERR El contenedor no inicio correctamente."
    docker compose logs --tail=20
    exit 1
fi
echo -e "$OK Contenedor mailserver corriendo."

# =============================================================
# PASO 6: Crear cuentas de correo
# =============================================================
echo -e "$INFO Creando cuentas de correo..."

# Funcion para crear cuenta si no existe
crear_cuenta() {
    local EMAIL="$1"
    local PASS="$2"
    if docker exec mailserver setup email list | grep -q "$EMAIL"; then
        echo -e "$WARN Cuenta ya existe: $EMAIL"
    else
        docker exec mailserver setup email add "$EMAIL" "$PASS"
        echo -e "$OK Cuenta creada: $EMAIL"
    fi
}

crear_cuenta "director@$DOMINIO"  "Director@2026!"
crear_cuenta "admin@$DOMINIO"     "Admin@2026!"

# =============================================================
# PASO 7: Configurar DKIM
# =============================================================
echo -e "$INFO Configurando DKIM para $DOMINIO..."

docker exec mailserver setup config dkim domain "$DOMINIO" keysize 2048

# Mostrar la clave publica DKIM para configurar en DNS
echo ""
echo -e "$INFO Clave publica DKIM (agregar en DNS como registro TXT):"
echo "  Nombre: mail._domainkey.$DOMINIO"
echo "  Valor:"
if [ -f "$DIR_CONFIG/opendkim/keys/$DOMINIO/mail.txt" ]; then
    cat "$DIR_CONFIG/opendkim/keys/$DOMINIO/mail.txt"
else
    docker exec mailserver cat /tmp/docker-mailserver/opendkim/keys/$DOMINIO/mail.txt 2>/dev/null || \
    echo -e "$WARN No se encontro la clave DKIM todavia. Revisa $DIR_CONFIG/opendkim/keys/$DOMINIO/"
fi

# =============================================================
# PASO 8: Configurar registros DNS simulados (bind local)
# =============================================================
echo ""
echo -e "$INFO Configurando zona DNS local para $DOMINIO..."

# Instalar bind si no esta instalado
if ! command -v named &>/dev/null; then
    echo -e "$INFO Instalando bind9..."
    dnf install -y bind bind-utils -q
fi

ZONA_FILE="/var/named/$DOMINIO.zone"

cat > "$ZONA_FILE" << ZONA
\$TTL 86400
@   IN  SOA  ns1.$DOMINIO. admin.$DOMINIO. (
            2026010101 ; Serial
            3600       ; Refresh
            900        ; Retry
            604800     ; Expire
            86400 )    ; Minimum TTL

; Servidores de nombres
@       IN  NS   ns1.$DOMINIO.
ns1     IN  A    $IP_SERVIDOR

; Registro A del servidor de correo
mail    IN  A    $IP_SERVIDOR

; Registro MX
@       IN  MX   10 mail.$DOMINIO.

; Registro SPF
@       IN  TXT  "v=spf1 a mx ip4:$IP_SERVIDOR ~all"

; Registro DMARC
_dmarc  IN  TXT  "v=DMARC1; p=quarantine; rua=mailto:admin@$DOMINIO"
ZONA

echo -e "$OK Zona DNS creada: $ZONA_FILE"

# Agregar zona a named.conf.local
NAMED_LOCAL="/etc/named.conf"
if ! grep -q "$DOMINIO" "$NAMED_LOCAL" 2>/dev/null; then
    cat >> "$NAMED_LOCAL" << NAMED

zone "$DOMINIO" {
    type master;
    file "$ZONA_FILE";
};
NAMED
    echo -e "$OK Zona agregada a named.conf"
fi

# Habilitar y arrancar bind
systemctl enable named --now &>/dev/null
systemctl restart named
echo -e "$OK Bind DNS reiniciado."

# Apuntar el servidor a su propio DNS
if ! grep -q "nameserver $IP_SERVIDOR" /etc/resolv.conf; then
    sed -i "1s/^/nameserver $IP_SERVIDOR\n/" /etc/resolv.conf
    echo -e "$OK resolv.conf actualizado."
fi

# =============================================================
# PASO 9: Configurar Fail2Ban
# =============================================================
echo -e "$INFO Verificando Fail2Ban dentro del contenedor..."
docker exec mailserver fail2ban-client status 2>/dev/null && \
    echo -e "$OK Fail2Ban activo." || \
    echo -e "$WARN Fail2Ban iniciando, espera unos minutos."

# =============================================================
# PASO 10: Instalar tarea programada de respaldo
# =============================================================
echo -e "$INFO Configurando respaldo automatico cada 24 horas..."

CRON_LINE="0 2 * * * root $DIR_TAREA/backup.sh >> $DIR_TAREA/backups/backup.log 2>&1"
if ! grep -q "backup.sh" /etc/crontab 2>/dev/null; then
    echo "$CRON_LINE" >> /etc/crontab
    echo -e "$OK Tarea programada agregada (diario a las 2:00 AM)"
else
    echo -e "$OK Tarea programada ya existe."
fi

chmod +x "$DIR_TAREA/backup.sh"

# =============================================================
# RESUMEN FINAL
# =============================================================
echo ""
echo "  +============================================+"
echo "  |   CONFIGURACION COMPLETADA                |"
echo "  +============================================+"
echo ""
echo "  Servidor : $HOSTNAME_MAIL ($IP_SERVIDOR)"
echo "  Dominio  : $DOMINIO"
echo ""
echo "  Cuentas creadas:"
echo "    director@$DOMINIO  ->  Director@2026!"
echo "    admin@$DOMINIO     ->  Admin@2026!"
echo ""
echo "  Puertos abiertos:"
echo "    25   SMTP"
echo "    465  SMTPS"
echo "    587  SMTP Submission (TLS)"
echo "    143  IMAP STARTTLS"
echo "    993  IMAPS"
echo ""
echo "  Para verificar logs:"
echo "    docker exec mailserver tail -f /var/log/mail/mail.log"
echo ""
echo "  Para enviar correo de prueba:"
echo "    docker exec mailserver swaks --to admin@$DOMINIO --from director@$DOMINIO --server localhost"
echo ""
