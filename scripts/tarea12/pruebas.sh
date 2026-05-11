#!/bin/bash
# =============================================================
# pruebas.sh - Pruebas de aceptacion
# Tarea 12 - reprobados.com
# =============================================================

DOMINIO="reprobados.com"
IP_SERVIDOR="192.168.100.10"

OK="\e[32m[OK]\e[0m"
INFO="\e[36m[INFO]\e[0m"
WARN="\e[33m[WARN]\e[0m"
ERR="\e[31m[ERROR]\e[0m"
FAIL="\e[31m[FAIL]\e[0m"

echo ""
echo "  +============================================+"
echo "  |   PRUEBAS DE ACEPTACION - TAREA 12        |"
echo "  +============================================+"
echo ""

# =============================================================
# PRUEBA 12.1: Envio y recepcion local
# =============================================================
echo "--- PRUEBA 12.1: Envio y recepcion local ---"
echo ""

# Instalar swaks si no esta disponible
if ! docker exec mailserver which swaks &>/dev/null; then
    echo -e "$INFO Instalando swaks en el contenedor..."
    docker exec mailserver apt-get install -y swaks -q 2>/dev/null || true
fi

echo -e "$INFO Enviando correo de director@ a admin@..."
RESULTADO=$(docker exec mailserver swaks \
    --to "admin@$DOMINIO" \
    --from "director@$DOMINIO" \
    --server "localhost" \
    --port 25 \
    --body "Prueba de correo local - Tarea 12" \
    --header "Subject: Prueba 12.1 Tarea12" \
    2>&1)

if echo "$RESULTADO" | grep -q "250"; then
    echo -e "$OK Correo enviado exitosamente."
else
    echo -e "$FAIL No se pudo enviar el correo."
    echo "$RESULTADO"
fi

echo ""
echo -e "$INFO Verificando que el correo llego al buzon de admin@..."
sleep 3
CORREOS=$(docker exec mailserver find /var/mail -name "*.eml" -newer /tmp 2>/dev/null | wc -l)
if [ "$CORREOS" -gt 0 ] 2>/dev/null; then
    echo -e "$OK Correos encontrados en el buzon."
else
    # Buscar de otra forma
    docker exec mailserver ls /var/mail/reprobados.com/admin/new/ 2>/dev/null && \
        echo -e "$OK Correo en buzon de admin." || \
        echo -e "$WARN No se pudo verificar el buzon automaticamente."
fi

# =============================================================
# PRUEBA 12.2: Auditoria de registros (logging)
# =============================================================
echo ""
echo "--- PRUEBA 12.2: Auditoria de registros ---"
echo ""

echo -e "$INFO Mostrando ultimas entradas del log de correo:"
echo ""
docker exec mailserver tail -30 /var/log/mail/mail.log 2>/dev/null || \
docker logs mailserver 2>&1 | grep -i "postfix\|dovecot\|smtp\|imap" | tail -30

echo ""
echo -e "$INFO Buscando en el log el flujo del ultimo correo enviado:"
docker exec mailserver grep -i "director\|admin\|reprobados" /var/log/mail/mail.log 2>/dev/null | tail -20 || \
docker logs mailserver 2>&1 | grep -i "director\|admin" | tail -20

# =============================================================
# PRUEBA 12.3: Verificacion de Fail2Ban
# =============================================================
echo ""
echo "--- PRUEBA 12.3: Verificacion de Fail2Ban ---"
echo ""

echo -e "$INFO Estado actual de Fail2Ban:"
docker exec mailserver fail2ban-client status 2>/dev/null || echo -e "$WARN Fail2Ban no responde todavia."

echo ""
echo -e "$INFO Simulando 5 intentos fallidos de autenticacion IMAP..."
for i in 1 2 3 4 5; do
    echo -e "$INFO Intento fallido $i/5..."
    (echo -e "a001 LOGIN admin@$DOMINIO WrongPass$i\na002 LOGOUT" | \
        openssl s_client -connect $IP_SERVIDOR:993 -quiet 2>/dev/null) || true
    sleep 2
done

echo ""
echo -e "$INFO Verificando si la IP fue bloqueada:"
sleep 5
docker exec mailserver fail2ban-client status dovecot 2>/dev/null || \
docker exec mailserver fail2ban-client status 2>/dev/null || \
echo -e "$WARN Verificar manualmente: docker exec mailserver fail2ban-client status"

# =============================================================
# RESUMEN
# =============================================================
echo ""
echo "  +============================================+"
echo "  |   RESUMEN DE PRUEBAS                      |"
echo "  +============================================+"
echo ""
echo "  Prueba 12.1: Envio/recepcion - ver arriba"
echo "  Prueba 12.2: Logs en /var/log/mail/mail.log"
echo "  Prueba 12.3: Fail2Ban - ver estado arriba"
echo ""
echo "  Para Prueba 13.4 (respaldo/restauracion):"
echo "    1. ./backup.sh"
echo "    2. docker exec mailserver rm -rf /var/mail/reprobados.com/admin/new/*"
echo "    3. docker compose stop mailserver"
echo "    4. ./restore.sh"
echo "    5. Verificar que el correo volvio"
echo ""
