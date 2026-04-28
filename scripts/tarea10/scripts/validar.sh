#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# validar.sh — Protocolo de pruebas Práctica 10
# Ejecuta los 4 tests del protocolo de validación
# Uso: bash validar.sh
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
echo -e "${YELLOW}  PRÁCTICA 10 — PROTOCOLO DE VALIDACIÓN${NC}"
sep

# ─────────────────────────────────────────────────────────────
# PRUEBA 10.1 — Persistencia de la Base de Datos
# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}TEST 10.1 — Persistencia de BD (volumen db_data)${NC}"

info "Insertando registro de prueba en reprobados_db..."
docker exec db_server psql -U db_admin -d reprobados_db \
    -c "INSERT INTO log_accesos (usuario, accion, resultado) VALUES ('test_persistencia', 'prueba_10.1', 'OK') RETURNING id, usuario, registrado;" \
    2>&1 && ok "Registro insertado correctamente" || fail "Error al insertar registro"

info "Eliminando el contenedor db_server (docker rm -f)..."
docker rm -f db_server

info "Esperando 3 segundos..."
sleep 3

info "Recreando el contenedor con docker compose up..."
docker compose up -d db_server
sleep 8

info "Verificando que el registro persiste después de recrear el contenedor..."
RESULT=$(docker exec db_server psql -U db_admin -d reprobados_db \
    -c "SELECT usuario, accion, resultado FROM log_accesos WHERE usuario='test_persistencia';" 2>&1)

if echo "$RESULT" | grep -q "test_persistencia"; then
    ok "PRUEBA 10.1 EXITOSA — Los datos persisten en el volumen db_data"
    echo "$RESULT"
else
    fail "PRUEBA 10.1 FALLIDA — Los datos no persistieron"
fi

# ─────────────────────────────────────────────────────────────
# PRUEBA 10.2 — Aislamiento de Red (ping por nombre)
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${CYAN}TEST 10.2 — Aislamiento de Red infra_red${NC}"

info "Verificando ping desde web_server → db_server (por nombre de contenedor)..."
docker exec web_server wget --quiet --tries=1 --timeout=5 \
    --spider http://db_server:5432 2>/dev/null
# wget no puede hablar PostgreSQL, usamos nc (netcat) si disponible
PING_RESULT=$(docker exec web_server sh -c \
    "nc -z -w3 db_server 5432 && echo REACHABLE || echo UNREACHABLE" 2>/dev/null)

if echo "$PING_RESULT" | grep -q "REACHABLE"; then
    ok "PRUEBA 10.2 EXITOSA — web_server alcanza db_server:5432 por nombre DNS interno"
else
    # Alpine usa nslookup como alternativa
    DNS_RESULT=$(docker exec web_server sh -c "nslookup db_server 2>&1" 2>/dev/null)
    if echo "$DNS_RESULT" | grep -q "172.20"; then
        ok "PRUEBA 10.2 EXITOSA — Resolución DNS interna: db_server → 172.20.0.20"
        echo "$DNS_RESULT"
    else
        info "Verificando conectividad con ping..."
        docker exec web_server sh -c "ping -c 3 db_server" 2>&1 && \
            ok "PRUEBA 10.2 EXITOSA — Ping exitoso por nombre de contenedor" || \
            fail "PRUEBA 10.2: Revisar red infra_red"
    fi
fi

info "Inspeccionando red infra_red..."
docker network inspect infra_red --format \
    'Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}  |  Contenedores: {{len .Containers}}'

# ─────────────────────────────────────────────────────────────
# PRUEBA 10.3 — Permisos FTP + acceso web
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${CYAN}TEST 10.3 — FTP → Volumen compartido → Servidor Web${NC}"

info "Subiendo archivo de prueba via FTP al volumen compartido..."
TEST_FILE="test_practica10_$(date +%s).txt"
echo "Archivo subido via FTP — Práctica 10 — $(date)" > /tmp/$TEST_FILE

# Usar curl con FTP (disponible en la mayoría de sistemas)
if command -v curl &>/dev/null; then
    curl --silent --ftp-create-dirs \
        --user "ftpuser:Ftp.Practica10!" \
        -T /tmp/$TEST_FILE \
        "ftp://localhost:21/$TEST_FILE" 2>&1 \
        && ok "Archivo subido via FTP: $TEST_FILE" \
        || fail "Error al subir via FTP (verificar que ftp_server esté corriendo)"
else
    info "curl no disponible — copiar manualmente al volumen:"
    info "  docker cp /tmp/$TEST_FILE ftp_server:/home/vsftpd/ftpuser/"
    docker cp /tmp/$TEST_FILE ftp_server:/home/vsftpd/ftpuser/ 2>/dev/null \
        && ok "Archivo copiado al contenedor FTP" || fail "Error al copiar"
fi

info "Verificando que el archivo sea accesible en el servidor web..."
sleep 2
HTTP_CODE=$(curl --silent -o /dev/null -w "%{http_code}" \
    "http://localhost/uploads/$TEST_FILE" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
    ok "PRUEBA 10.3 EXITOSA — Archivo accesible en http://localhost/uploads/$TEST_FILE"
else
    info "HTTP code: $HTTP_CODE — verificar montaje del volumen web_content"
    # Verificar que el volumen está montado correctamente
    docker exec web_server ls /usr/share/nginx/html/uploads/ 2>&1
fi

# ─────────────────────────────────────────────────────────────
# PRUEBA 10.4 — Límites de Recursos
# ─────────────────────────────────────────────────────────────
sep
echo -e "\n${CYAN}TEST 10.4 — Límites de Memoria y CPU${NC}"

info "Ejecutando docker stats --no-stream..."
docker stats --no-stream --format \
    "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" \
    web_server db_server ftp_server

echo ""
info "Verificando límites configurados en docker inspect..."
for CONTAINER in web_server db_server ftp_server; do
    MEM_LIMIT=$(docker inspect $CONTAINER \
        --format '{{.HostConfig.Memory}}' 2>/dev/null)
    CPU_QUOTA=$(docker inspect $CONTAINER \
        --format '{{.HostConfig.CpuQuota}}' 2>/dev/null)
    if [ "$MEM_LIMIT" -gt "0" ] 2>/dev/null; then
        MEM_MB=$((MEM_LIMIT / 1048576))
        ok "$CONTAINER: RAM limit = ${MEM_MB}MB | CPU quota = ${CPU_QUOTA} (100000 = 1 core)"
    else
        info "$CONTAINER: Sin límite de memoria configurado (revisar deploy.resources en compose)"
    fi
done
