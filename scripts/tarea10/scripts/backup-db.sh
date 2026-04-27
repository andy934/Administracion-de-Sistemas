#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# backup-db.sh — Respaldo automatizado de PostgreSQL
# Ejecutar con: bash backup-db.sh
# Programar con cron: 0 2 * * * /ruta/practica10/scripts/backup-db.sh
# ═══════════════════════════════════════════════════════════════

CONTAINER="db_server"
DB_NAME="reprobados_db"
DB_USER="db_admin"
BACKUP_DIR="$(dirname "$0")/../backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/backup_${DB_NAME}_${TIMESTAMP}.sql.gz"

# Crear directorio de backups si no existe
mkdir -p "$BACKUP_DIR"

echo "[$(date)] Iniciando respaldo de $DB_NAME..."

# Ejecutar pg_dump dentro del contenedor y comprimir
docker exec -t "$CONTAINER" \
    pg_dump -U "$DB_USER" "$DB_NAME" \
    | gzip > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "[$(date)] ✓ Respaldo completado: $BACKUP_FILE ($SIZE)"
else
    echo "[$(date)] ✗ ERROR: Falló el respaldo de $DB_NAME"
    exit 1
fi

# Eliminar respaldos con más de 7 días
find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +7 -delete
echo "[$(date)] Respaldos anteriores a 7 días eliminados."

# Listar respaldos existentes
echo ""
echo "Respaldos disponibles:"
ls -lh "$BACKUP_DIR"/backup_*.sql.gz 2>/dev/null || echo "  (ninguno)"
