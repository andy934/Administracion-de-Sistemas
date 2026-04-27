# ─────────────────────────────────────────────────────────────
# Práctica 10 — Servidor Web Personalizado
# Base: nginx:alpine (imagen ligera)
# Seguridad: usuario no-root, server_tokens off, headers mínimos
# ─────────────────────────────────────────────────────────────
FROM nginx:alpine

LABEL maintainer="admin@reprobados.local"
LABEL description="Servidor web personalizado Practica 10 — reprobados.local"

# ── Seguridad: eliminar firmas del servidor ──────────────────
# Copia configuración nginx que desactiva server_tokens
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf

# ── Contenido web personalizado ──────────────────────────────
COPY html/ /usr/share/nginx/html/

# ── Usuario no administrativo ────────────────────────────────
# nginx:alpine ya incluye el usuario 'nginx' (UID 101)
# Ajustar permisos para que nginx pueda leer los archivos
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown nginx:nginx /var/run/nginx.pid

# Exponer puerto no privilegiado (8080) para correr sin root
EXPOSE 8080

# Ejecutar como usuario no-root
USER nginx

CMD ["nginx", "-g", "daemon off;"]
