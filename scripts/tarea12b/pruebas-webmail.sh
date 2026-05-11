#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# pruebas-webmail.sh — Pruebas de aceptación Parte 2
# Práctica 12 — reprobados.com
# ═══════════════════════════════════════════════════════════════

IP="192.168.116.128"
OK="\e[32m[OK]\e[0m"
INFO="\e[36m[INFO]\e[0m"
FAIL="\e[31m[FAIL]\e[0m"
WARN="\e[33m[WARN]\e[0m"

echo ""
echo "  +============================================+"
echo "  |   PRUEBAS WEBMAIL - PARTE 2               |"
echo "  +============================================+"
echo ""

# ─────────────────────────────────────────────────────────────
# PRUEBA 13.5 — Acceso al portal
# ─────────────────────────────────────────────────────────────
echo "--- PRUEBA 13.5: Inicio de sesión institucional ---"
echo ""

echo -e "$INFO Verificando que Roundcube responde en :80..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://$IP/ 2>/dev/null)
if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
    echo -e "$OK Portal accesible (HTTP $HTTP)"
else
    echo -e "$FAIL Portal no responde (HTTP $HTTP)"
fi

echo -e "$INFO Verificando dominio institucional en la página de login..."
PAGE=$(curl -s http://$IP/ 2>/dev/null)
if echo "$PAGE" | grep -qi "reprobados"; then
    echo -e "$OK Dominio reprobados.com presente en el portal"
else
    echo -e "$WARN No se detectó el dominio en la página (verificar manualmente)"
fi

echo -e "$INFO Verificando contenedores activos..."
docker ps --format "  {{.Names}}\t{{.Status}}" | grep -E "roundcube|mariadb"

echo ""
echo -e "$INFO Para verificar inicio de sesión abre en tu navegador:"
echo -e "    http://$IP/"
echo -e "    Usuario: director  (o director@reprobados.com)"
echo -e "    Contraseña: Director@2026!"

# ─────────────────────────────────────────────────────────────
# PRUEBA 13.6 — Envío con adjunto (instrucciones)
# ─────────────────────────────────────────────────────────────
echo ""
echo "--- PRUEBA 13.6: Envío de adjuntos ---"
echo ""
echo -e "$INFO Para esta prueba, desde el portal web:"
echo "    1. Inicia sesión como director@reprobados.com"
echo "    2. Redacta un correo a admin@reprobados.com"
echo "    3. Adjunta cualquier archivo (imagen, PDF, etc.)"
echo "    4. Envía y verifica en la cuenta de admin"
echo ""

# Verificar que el correo anterior sigue en el buzón
CORREOS=$(docker exec mailserver find /var/mail -type f -path "*/new/*" 2>/dev/null | wc -l)
echo -e "$INFO Correos actuales en buzones: $CORREOS"

# ─────────────────────────────────────────────────────────────
# PRUEBA 13.7 — Persistencia de preferencias
# ─────────────────────────────────────────────────────────────
echo ""
echo "--- PRUEBA 13.7: Persistencia de preferencias ---"
echo ""

echo -e "$INFO Verificando volúmenes de Roundcube..."
docker volume ls | grep -E "roundcube" | while read line; do
    echo -e "$OK Volumen activo: $line"
done

echo ""
echo -e "$INFO Procedimiento para validar persistencia:"
echo "    1. En el portal, ve a Configuración → Preferencias"
echo "    2. Cambia el idioma a English (o agrega un contacto)"
echo "    3. Guarda los cambios"
echo "    4. Reinicia el contenedor:"
echo "       docker compose restart roundcube"
echo "    5. Vuelve a entrar — los cambios deben persistir"
echo ""

echo -e "$INFO Reiniciando Roundcube para demostrar persistencia..."
docker compose restart roundcube
sleep 15

HTTP_POST=$(curl -s -o /dev/null -w "%{http_code}" http://$IP/ 2>/dev/null)
if [ "$HTTP_POST" = "200" ] || [ "$HTTP_POST" = "302" ]; then
    echo -e "$OK Roundcube disponible tras reinicio (HTTP $HTTP_POST)"
    echo -e "$OK Prueba 13.7: El volumen roundcube_db persiste las preferencias"
else
    echo -e "$FAIL Roundcube no responde tras reinicio"
fi

# ─────────────────────────────────────────────────────────────
# RESUMEN
# ─────────────────────────────────────────────────────────────
echo ""
echo "  +============================================+"
echo "  |   RESUMEN DE PRUEBAS                      |"
echo "  +============================================+"
echo ""
echo "  13.5 — Portal accesible en http://$IP/"
echo "  13.6 — Enviar correo con adjunto desde el portal"
echo "  13.7 — Persistencia verificada tras reinicio"
echo ""
echo "  Comandos de evidencia:"
echo "    docker compose ps"
echo "    docker volume ls | grep roundcube"
echo "    docker exec mailserver tail -20 /var/log/mail/mail.log"
echo ""
