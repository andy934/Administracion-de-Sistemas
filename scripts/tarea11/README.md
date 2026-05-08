# Práctica 11 — Orquestación Multicapa con Docker Compose

## Estructura del proyecto

```
practica11/
├── docker-compose.yml       # Orquestador principal
├── .env                     # Credenciales (nunca subir a git)
├── nginx/
│   ├── nginx.conf           # Balanceador + server_tokens off
│   └── html/
│       └── index.html       # Página pública del balanceador
├── app/
│   └── html/
│       └── index.html       # App interna (acceso solo vía /app/)
└── scripts/
    └── validar.sh           # Protocolo de pruebas automatizado
```

## Arquitectura

```
[Tu PC]
   │
   ▼ :80
[nginx_balanceador]  ← red_publica →  [app_server]
                                           (sin puertos al host)
   │ túnel SSH
   ▼
[shadou@192.168.116.128]
   │
   ├── red_datos → [db_server:5432]   (sin puertos al host)
   └── 127.0.0.1:5050 → [pgadmin]    (solo localhost)
```

## Despliegue

```bash
# 1. Levantar todo
docker compose up -d

# 2. Verificar estado
docker compose ps

# 3. Ejecutar protocolo de pruebas
bash scripts/validar.sh
```

## Prueba 11.3 — Túnel SSH hacia pgAdmin

Desde **tu PC** (no desde el servidor), ejecuta:

```bash
ssh -L 8080:127.0.0.1:5050 shadou@192.168.116.128
```

Luego abre en tu navegador: **http://localhost:8080**

| Campo    | Valor                   |
|----------|-------------------------|
| Email    | admin@reprobados.local  |
| Password | PgAdmin.11!             |

## Prueba 11.4 — Reinicio con persistencia

```bash
# Detener todo (los volúmenes persisten)
docker compose down

# Volver a levantar
docker compose up -d

# pgAdmin esperará a que db_server esté healthy antes de subir
docker compose ps
```

## Verificar aislamiento de red (Prueba 11.1)

```bash
# Desde tu PC o desde el servidor — debe fallar o dar timeout
curl http://192.168.116.128:5432
curl http://192.168.116.128:5050   # también debe fallar (solo localhost)

# Esto SÍ debe funcionar
curl http://192.168.116.128/
curl http://192.168.116.128/app/
```

## Servicios y redes

| Contenedor       | Red          | Puerto host         | Descripción               |
|------------------|--------------|---------------------|---------------------------|
| nginx_balanceador | red_publica | 80                  | Único punto público       |
| app_server        | red_publica | ninguno             | App interna vía proxy     |
| db_server         | red_datos   | ninguno             | PostgreSQL aislado        |
| pgadmin           | red_datos   | 127.0.0.1:5050      | Solo vía túnel SSH        |
