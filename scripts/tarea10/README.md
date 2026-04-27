# Práctica 10 — Virtualización, Persistencia y Seguridad en Contenedores

## Estructura del proyecto

```
practica10/
├── docker-compose.yml          # Orquestador principal
├── backups/                    # Respaldos de PostgreSQL (generados automáticamente)
├── web/
│   ├── Dockerfile              # Imagen personalizada nginx:alpine
│   ├── nginx.conf              # Config global (server_tokens off)
│   ├── default.conf            # Virtual host en puerto 8080
│   └── html/
│       ├── index.html          # Página web personalizada
│       ├── css/style.css
│       ├── js/canvas.js
│       └── uploads/            # Montado como volumen web_content
└── scripts/
    ├── init-db.sql             # Inicialización de BD (se ejecuta automático)
    ├── backup-db.sh            # Respaldo manual/programado de PostgreSQL
    └── validar.sh              # Protocolo de pruebas automatizado
```

## Despliegue

### 1. Construir y levantar todos los servicios
```bash
docker compose up -d --build
```

### 2. Verificar que todos están corriendo
```bash
docker compose ps
docker stats --no-stream
```

### 3. Ejecutar el protocolo de validación completo
```bash
bash scripts/validar.sh
```

### 4. Programar respaldo automático (cron)
```bash
# Respaldo diario a las 2:00 AM
echo "0 2 * * * $(pwd)/scripts/backup-db.sh >> $(pwd)/backups/backup.log 2>&1" | crontab -
```

## Prueba manual de persistencia (Prueba 10.1)
```bash
# Insertar dato
docker exec db_server psql -U db_admin -d reprobados_db \
  -c "INSERT INTO usuarios (usuario, nombre, apellido, depto) VALUES ('test_user', 'Test', 'User', 'Prueba');"

# Eliminar y recrear el contenedor
docker rm -f db_server
docker compose up -d db_server && sleep 8

# Verificar que el dato persiste
docker exec db_server psql -U db_admin -d reprobados_db \
  -c "SELECT * FROM usuarios WHERE usuario='test_user';"
```

## Conexión a la BD desde web_server (Prueba 10.2)
```bash
# Desde dentro del contenedor web — resolución DNS por nombre
docker exec web_server sh -c "nslookup db_server"
docker exec web_server sh -c "ping -c 3 ftp_server"
```

## Subir archivo via FTP (Prueba 10.3)
```bash
# Con curl
curl --ftp-create-dirs --user "ftpuser:Ftp.Practica10!" \
  -T /ruta/archivo.txt ftp://localhost:21/archivo.txt

# Verificar en el servidor web
curl http://localhost/uploads/archivo.txt
```

## Verificar límites de recursos (Prueba 10.4)
```bash
docker stats --no-stream
docker inspect web_server --format 'Mem: {{.HostConfig.Memory}} CPU: {{.HostConfig.CpuQuota}}'
```

## Credenciales

| Servicio    | Usuario    | Contraseña           | Puerto |
|-------------|------------|----------------------|--------|
| PostgreSQL  | db_admin   | Practica10.Segura!   | 5432 (interno) |
| FTP         | ftpuser    | Ftp.Practica10!      | 21     |
| Web         | —          | —                    | 80     |

## Recursos configurados

| Contenedor  | RAM límite | CPU límite | IP           |
|-------------|------------|------------|--------------|
| web_server  | 512 MB     | 0.5 cores  | 172.20.0.10  |
| db_server   | 512 MB     | 0.5 cores  | 172.20.0.20  |
| ftp_server  | 256 MB     | 0.25 cores | 172.20.0.30  |
