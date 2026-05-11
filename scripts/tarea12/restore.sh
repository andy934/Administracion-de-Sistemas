#!/bin/bash
# =============================================================
# restore.sh - Restaurar buzones desde un respaldo
# Tarea 12 - reprobados.com
# Prueba 13.4: Integridad de respaldo
# =============================================================

DIR_TAREA="$(cd "$(dirname "$0")" && pwd)"
DIR_BACKUPS="$DIR_TAREA/backups"

echo ""
echo "  +============================================+"
echo "  |   RESTAURACION DE BUZONES                 |"
echo "  +============================================+"
echo ""

# Listar respaldos disponibles
echo "  Respaldos disponibles:"
echo ""
ls -lh "$DIR_BACKUPS"/mail_backup_*.tar.gz 2>/dev/null || {
    echo "  [ERROR] No hay respaldos disponibles en $DIR_BACKUPS"
    exit 1
}

echo ""
read -p "  Ingresa el nombre del archivo a restaurar: " ARCHIVO

if [ ! -f "$DIR_BACKUPS/$ARCHIVO" ]; then
    echo "  [ERROR] Archivo no encontrado: $ARCHIVO"
    exit 1
fi

echo ""
echo "  [WARN] Esto sobreescribira los datos actuales del volumen mail_data."
read -p "  ¿Continuar? (s/n): " CONFIRMAR

if [ "$CONFIRMAR" != "s" ]; then
    echo "  Restauracion cancelada."
    exit 0
fi

# Detener el contenedor
echo "  [INFO] Deteniendo contenedor mailserver..."
cd "$DIR_TAREA"
docker compose stop mailserver

# Restaurar el volumen
echo "  [INFO] Restaurando desde $ARCHIVO..."
docker run --rm \
    -v mail_data:/var/mail \
    -v mail_state:/var/mail-state \
    -v "$DIR_BACKUPS":/backup \
    alpine \
    tar xzf "/backup/$ARCHIVO" -C /

if [ $? -eq 0 ]; then
    echo "  [OK] Datos restaurados correctamente."
else
    echo "  [ERROR] Fallo la restauracion."
    exit 1
fi

# Reiniciar el contenedor
echo "  [INFO] Reiniciando contenedor mailserver..."
docker compose start mailserver
sleep 10

echo ""
echo "  [OK] Restauracion completada."
echo "  Verifica los correos conectandote por IMAP o con:"
echo "    docker exec mailserver find /var/mail -name '*.eml' | head -20"
echo ""
