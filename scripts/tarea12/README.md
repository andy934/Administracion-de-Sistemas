# Tarea 12 - Servidor de Correo reprobados.com

## Arquitectura
- **Postfix** - SMTP (envio)
- **Dovecot** - IMAP (recepcion)
- **Rspamd** - Filtro antispam
- **Fail2Ban** - Bloqueo de IPs maliciosas
- **OpenDKIM** - Firma digital de correos

## Servidor
- IP: 192.168.116.128
- Dominio: reprobados.com
- Hostname: mail.reprobados.com

## Instalacion

```bash
# 1. Copiar esta carpeta al servidor
scp -r tarea12/ usuario@192.168.116.128:~/

# 2. Conectarse al servidor
ssh usuario@192.168.116.128

# 3. Entrar a la carpeta
cd ~/tarea12

# 4. Dar permisos de ejecucion
chmod +x setup.sh backup.sh restore.sh pruebas.sh

# 5. Ejecutar como root
sudo ./setup.sh
```

## Cuentas de correo
| Cuenta | Contraseña |
|--------|-----------|
| director@reprobados.com | Director@2026! |
| admin@reprobados.com | Admin@2026! |

## Puertos
| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| 25 | SMTP | Recepcion entre servidores |
| 465 | SMTPS | Envio con SSL |
| 587 | SMTP | Envio con STARTTLS |
| 143 | IMAP | Recepcion con STARTTLS |
| 993 | IMAPS | Recepcion con SSL |

## Comandos utiles

```bash
# Ver logs en tiempo real
docker exec mailserver tail -f /var/log/mail/mail.log

# Listar cuentas
docker exec mailserver setup email list

# Agregar cuenta
docker exec mailserver setup email add usuario@reprobados.com Contraseña123!

# Ver estado de Fail2Ban
docker exec mailserver fail2ban-client status

# Ver IPs bloqueadas
docker exec mailserver fail2ban-client status dovecot

# Hacer respaldo manual
sudo ./backup.sh

# Restaurar respaldo
sudo ./restore.sh

# Ejecutar pruebas de aceptacion
sudo ./pruebas.sh
```

## Pruebas de aceptacion

### Prueba 12.1 - Envio y recepcion local
```bash
docker exec mailserver swaks \
  --to admin@reprobados.com \
  --from director@reprobados.com \
  --server localhost --port 25 \
  --body "Prueba de correo"
```

### Prueba 12.2 - Auditoria de logs
```bash
docker exec mailserver tail -50 /var/log/mail/mail.log
```

### Prueba 12.3 - Fail2Ban
```bash
# Intentar 5 logins fallidos y verificar bloqueo
docker exec mailserver fail2ban-client status dovecot
```

### Prueba 13.4 - Restauracion de respaldo
```bash
./backup.sh                    # 1. Hacer respaldo
# borrar un correo manualmente
docker compose stop mailserver  # 2. Detener contenedor
./restore.sh                    # 3. Restaurar
# verificar que el correo volvio
```

## Configuracion de cliente de correo (Thunderbird/Mailspring)

- **Servidor entrante (IMAP)**
  - Servidor: 192.168.116.128
  - Puerto: 993
  - SSL: SSL/TLS
  - Usuario: director@reprobados.com

- **Servidor saliente (SMTP)**
  - Servidor: 192.168.116.128
  - Puerto: 587
  - SSL: STARTTLS
  - Usuario: director@reprobados.com
