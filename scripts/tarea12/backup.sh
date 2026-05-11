#!/bin/bash
# =============================================================
# backup.sh - Respaldo automatico de buzones cada 24 horas
# Tarea 12 - reprobados.com
# =============================================================

DIR_TAREA="$(cd "$(dirname "$0")" && pwd)"
DIR_BACKUPS="$DIR_TAREA/backups"
FECHA=$(date +"%Y%m%d_%H%M%S")
ARCHIVO_BACKUP="$DIR_BACKUPS/mail_backup_$FECHA.tar.gz"
RETENTION_DIAS=7

echo "========================================"
echo "  RESPALDO DE BUZONES - $(date)"
echo "========================================"

# Crear directorio de backups si no existe
mkdir -p "$DIR_BACKUPS"

# Verificar que el contenedor esta corriendo
if ! docker ps | grep -q mailserver; then
    echo "[ERROR] El contenedor mailserver no esta corriendo."
    exit 1
fi

echo "[INFO] Iniciando respaldo del volumen mail_data..."

# Crear respaldo comprimido del volumen mail_data
docker run --rm \
    -v mail_data:/var/mail:ro \
    -v mail_state:/var/mail-state:ro \
    -v "$DIR_BACKUPS":/backup \
    alpine \
    tar czf "/backup/mail_backup_$FECHA.tar.gz" \
        -C / var/mail var/mail-state \
        --warning=no-file-changed

if [ $? -eq 0 ]; then
    TAMANO=$(du -sh "$ARCHIVO_BACKUP" | cut -f1)
    echo "[OK] Respaldo creado: $ARCHIVO_BACKUP ($TAMANO)"
else
    echo "[ERROR] Fallo la creacion del respaldo."
    exit 1
fi

# Eliminar respaldos mas antiguos que RETENTION_DIAS dias
echo "[INFO] Eliminando respaldos con mas de $RETENTION_DIAS dias..."
find "$DIR_BACKUPS" -name "mail_backup_*.tar.gz" -mtime +$RETENTION_DIAS -delete
echo "[OK] Limpieza completada."

# Mostrar respaldos disponibles
echo ""
echo "[INFO] Respaldos disponibles:"
ls -lh "$DIR_BACKUPS"/mail_backup_*.tar.gz 2>/dev/null || echo "  (ninguno)"
echo ""
echo "[OK] Respaldo finalizado: $(date)"
echo "========================================"
