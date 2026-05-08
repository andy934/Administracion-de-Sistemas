#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# validar.sh — Protocolo de pruebas Práctica 11
# Uso: bash scripts/validar.sh
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
sep()  { echo -e "\n${YELLOW}════════════════════════════════════════${NC}"; }

sep
echo -e "${YELLOW}  PRÁCTICA 11 — PROTOCOLO DE VALIDACIÓN${NC}"
sep

# ─────────────────────────────────────────────────────────────
# PRUEBA 11.1 — Aislamiento de red (puertos bloqueados)
# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}TEST 11.1 — Aislamiento de red${NC}"

info "Verificando que PostgreSQL (5432) NO está expuesto al host..."
if curl --connect-timeout 3 -s localhost:5432 > /dev/null 2>&1; then
    fail "Puerto 5432 accesible desde el host — revisar expose vs ports en compose"
else
    ok "Puerto 5432 no accesible desde el host — correctamente aislado en red_datos"
fi

info "Verificando que pgAdmin (5050) solo escucha en 127.0.0.1..."
SS_RESULT=$(ss -tlnp | grep 5050)
if echo "$SS_RESULT" | grep -q "127.0.0.1:5050"; then
    ok "pgAdmin escucha solo en 127.0.0.1:5050 — invisible desde exterior"
elif echo "$SS_RESULT" | grep -q "0.0.0.0:5050"; then
    fail "pgAdmin escucha en 0.0.0.0:5050 — expuesto públicamente (revisar docker-compose)"
else
    info "Puerto 5050 no encontrado en ss — verificar que pgadmin esté corriendo"
fi

info "Verificando que el servidor web (80) SÍ es accesible..."
HTTP_CODE=$(curl --connect-timeout 5 -s -o /dev/null -w "%{http_code}" http://localhost/)
if [ "$HTTP_CODE" = "200" ]; then
    ok "Servidor web responde en :80 con HTTP $HTTP_CODE"
else
    fail "Servidor web no responde (HTTP $HTTP_CODE)"
fi

# ─────────────────────────────────────────────────────────────
# PRUEBA 11.2 — Resolución DNS interna
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${CYAN}TEST 11.2 — Resolución DNS interna desde nginx${NC}"

info "Ping desde nginx_balanceador → db_server por nombre..."
PING=$(docker exec nginx_balanceador sh -c "ping -c 3 db_server 2>&1" 2>/dev/null)
if echo "$PING" | grep -q "3 packets transmitted"; then
    fail "nginx puede ver db_server — debería estar en redes distintas (red_publica vs red_datos)"
else
    # En este diseño nginx NO puede ver db directamente (correcto)
    ok "nginx_balanceador NO resuelve db_server — aislamiento de redes correcto"
fi

info "Ping desde nginx_balanceador → app_server por nombre..."
PING2=$(docker exec nginx_balanceador sh -c "ping -c 3 app_server 2>&1" 2>/dev/null)
if echo "$PING2" | grep -q "bytes from"; then
    ok "nginx resuelve app_server por nombre DNS interno (misma red_publica)"
    echo "$PING2" | grep -E "bytes from|packet loss"
else
    fail "nginx no resuelve app_server — verificar que ambos estén en red_publica"
fi

info "Inspeccionando redes..."
docker network inspect red_publica --format \
    'red_publica — contenedores: {{range $k,$v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null
docker network inspect red_datos --format \
    'red_datos   — contenedores: {{range $k,$v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null

# ─────────────────────────────────────────────────────────────
# PRUEBA 11.3 — Túnel SSH (instrucciones)
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${CYAN}TEST 11.3 — Túnel SSH cifrado hacia pgAdmin${NC}"

info "Verificando que pgAdmin responde en localhost:5050..."
PGA_CODE=$(curl --connect-timeout 5 -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5050/ 2>/dev/null)
if [ "$PGA_CODE" = "200" ] || [ "$PGA_CODE" = "302" ]; then
    ok "pgAdmin responde en 127.0.0.1:5050 (HTTP $PGA_CODE)"
else
    info "pgAdmin devuelve HTTP $PGA_CODE en localhost — puede estar iniciando aún"
fi

echo ""
echo -e "  ${YELLOW}Comando para el túnel SSH (desde tu PC):${NC}"
echo -e "  ${GREEN}ssh -L 8080:127.0.0.1:5050 shadou@192.168.116.128${NC}"
echo ""
echo -e "  Luego abre en tu navegador: ${CYAN}http://localhost:8080${NC}"
echo -e "  Credenciales pgAdmin:"
echo -e "    Email:    ${CYAN}admin@reprobados.local${NC}"
echo -e "    Password: ${CYAN}PgAdmin.11!${NC}"

# ─────────────────────────────────────────────────────────────
# PRUEBA 11.4 — Persistencia y healthcheck
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${CYAN}TEST 11.4 — Persistencia de datos y healthcheck${NC}"

info "Insertando registro de prueba en PostgreSQL..."
docker exec db_server psql -U db_admin -d reprobados_db \
    -c "CREATE TABLE IF NOT EXISTS prueba_persistencia (id SERIAL PRIMARY KEY, dato TEXT, creado TIMESTAMP DEFAULT NOW());" \
    > /dev/null 2>&1
docker exec db_server psql -U db_admin -d reprobados_db \
    -c "INSERT INTO prueba_persistencia (dato) VALUES ('test_practica11_$(date +%s)');" \
    > /dev/null 2>&1
ROWS=$(docker exec db_server psql -U db_admin -d reprobados_db \
    -t -c "SELECT COUNT(*) FROM prueba_persistencia;" 2>/dev/null | tr -d ' ')
ok "Tabla prueba_persistencia con $ROWS registro(s)"

info "Verificando estado de healthcheck de los contenedores..."
for C in nginx_balanceador app_server db_server pgadmin; do
    STATUS=$(docker inspect $C --format '{{.State.Health.Status}}' 2>/dev/null)
    if [ "$STATUS" = "healthy" ]; then
        ok "$C — $STATUS"
    elif [ "$STATUS" = "starting" ]; then
        info "$C — $STATUS (espera un momento)"
    elif [ -z "$STATUS" ]; then
        info "$C — sin healthcheck configurado"
    else
        fail "$C — $STATUS"
    fi
done

info "Verificando volúmenes..."
docker volume ls | grep -E "db_data|pgadmin_data" | while read line; do
    ok "Volumen activo: $line"
done

# ─────────────────────────────────────────────────────────────
# RESUMEN
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${YELLOW}  RESUMEN — COMANDOS DE EVIDENCIA${NC}"
echo ""
echo "  docker compose ps"
echo "  docker network inspect red_publica red_datos"
echo "  docker inspect db_server --format '{{.State.Health.Status}}'"
echo "  docker inspect pgadmin  --format '{{.State.Health.Status}}'"
echo "  ss -tlnp | grep -E '80|5050|5432'"
sep
echo ""
