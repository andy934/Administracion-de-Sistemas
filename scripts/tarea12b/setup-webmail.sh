#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# setup-webmail.sh — Despliegue del portal Roundcube
# Práctica 12 Parte 2 — reprobados.com
# ═══════════════════════════════════════════════════════════════

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
OK="\e[32m[OK]\e[0m"
INFO="\e[36m[INFO]\e[0m"
ERR="\e[31m[ERROR]\e[0m"

echo ""
echo "  +============================================+"
echo "  |   SETUP WEBMAIL ROUNDCUBE - PARTE 2       |"
echo "  |   Dominio: reprobados.com                 |"
echo "  +============================================+"
echo ""

# ── Verificar que mailserver esté corriendo ─────────────────────
echo -e "$INFO Verificando que mailserver está activo..."
if ! docker ps | grep -q "mailserver"; then
    echo -e "$ERR El contenedor mailserver no está corriendo."
    echo -e "    Ejecuta primero: cd ../tarea12 && sudo ./setup.sh"
    exit 1
fi
echo -e "$OK mailserver activo."

# ── Verificar puerto 80 libre ────────────────────────────────────
echo -e "$INFO Verificando puerto 80..."
if ss -tlnp | grep -q ":80 "; then
    echo -e "$ERR Puerto 80 en uso. Detén el servicio que lo ocupa:"
    ss -tlnp | grep ":80 "
    exit 1
fi
echo -e "$OK Puerto 80 libre."

# ── Conectar mailserver a mail_network ───────────────────────────
echo -e "$INFO Conectando mailserver a la red mail_network..."
docker network create mail_network 2>/dev/null || true
docker network connect mail_network mailserver 2>/dev/null && \
    echo -e "$OK mailserver conectado a mail_network." || \
    echo -e "$OK mailserver ya está en mail_network."

# ── Levantar Roundcube + MariaDB ─────────────────────────────────
echo -e "$INFO Levantando Roundcube y MariaDB..."
cd "$DIR"
docker compose up -d

echo -e "$INFO Esperando que los servicios inicien (45s)..."
sleep 45

# ── Verificar estado ─────────────────────────────────────────────
echo -e "$INFO Verificando contenedores..."
docker compose ps

# ── Prueba de acceso HTTP ────────────────────────────────────────
echo -e "$INFO Probando acceso al portal..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ 2>/dev/null)
if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
    echo -e "$OK Portal accesible en http://192.168.116.128/ (HTTP $HTTP)"
else
    echo -e "$ERR Portal no responde (HTTP $HTTP)"
    echo "    Revisa: docker logs roundcube_webmail --tail 20"
fi

echo ""
echo "  +============================================+"
echo "  |   PORTAL WEBMAIL LISTO                    |"
echo "  +============================================+"
echo ""
echo "  URL:      http://192.168.116.128/"
echo "  Cuentas:"
echo "    director@reprobados.com  /  Director@2026!"
echo "    admin@reprobados.com     /  Admin@2026!"
echo ""
echo "  Nota: El usuario solo necesita escribir 'director'"
echo "  (el dominio @reprobados.com se agrega automático)"
echo ""
