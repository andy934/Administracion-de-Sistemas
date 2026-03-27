ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
BLANCO='\033[1;37m'
RESET='\033[0m'

DOMINIO="practica8.local"
DOMINIO_UPPER="PRACTICA8"
SERVIDOR_IP="192.168.10.11"

if [ "$EUID" -ne 0 ]; then
    echo ""
    echo -e "  ${ROJO}[ERROR] Este script debe ejecutarse como root.${RESET}"
    echo -e "  Usa: sudo bash unir_linux.sh"
    echo ""
    exit 1
fi

clear
echo ""
echo -e "  ${CYAN}+==========================================+${RESET}"
echo -e "  ${CYAN}|     UNIR CLIENTE LINUX AL DOMINIO        |${RESET}"
echo -e "  ${CYAN}+==========================================+${RESET}"
echo ""

# --- Verificar conectividad con el servidor ---
echo -e "  ${AMARILLO}Verificando conectividad con el servidor...${RESET}"
echo ""

if ! ping -c 2 -W 2 $SERVIDOR_IP &>/dev/null; then
    echo -e "  ${ROJO}[ERROR] No se puede contactar al servidor $SERVIDOR_IP${RESET}"
    echo -e "  ${AMARILLO}Verifica que el servidor este encendido y el adaptador red_sistemas activo.${RESET}"
    echo ""
    exit 1
fi
echo -e "  ${VERDE}[OK] Servidor alcanzable.${RESET}"

# --- Verificar si ya esta en el dominio ---
echo ""
echo -e "  ${AMARILLO}Verificando estado actual del dominio...${RESET}"

if realm list 2>/dev/null | grep -q "$DOMINIO"; then
    echo -e "  ${AMARILLO}[INFO] Esta maquina ya esta unida al dominio $DOMINIO.${RESET}"
    echo -e "  ${AMARILLO}No es necesario unirla de nuevo.${RESET}"
    echo ""
    exit 0
fi

# --- Configurar DNS apuntando al servidor AD ---
echo ""
echo -e "  ${AMARILLO}Configurando DNS para apuntar al servidor AD...${RESET}"

# Detectar el adaptador con IP del servidor DNS
ADAPTADOR=$(ip -o -4 addr show | awk '$4 == "192.168.10.11/24" {print $2}' | head -1)

if [ -n "$ADAPTADOR" ]; then
    echo -e "  ${VERDE}[OK] Adaptador encontrado: $ADAPTADOR${RESET}"
else
    echo -e "  ${AMARILLO}[AVISO] No se encontro adaptador con IP 192.168.10.11, usando configuracion general.${RESET}"
fi

# Configurar DNS via resolv.conf y systemd-resolved
cat > /etc/resolv.conf << EOF
# Configurado por unir_linux.sh para practica8.local
nameserver $SERVIDOR_IP
search $DOMINIO
EOF

# Si systemd-resolved esta activo, configurarlo tambien
if systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d/
    cat > /etc/systemd/resolved.conf.d/practica8.conf << EOF
[Resolve]
DNS=$SERVIDOR_IP
Domains=$DOMINIO
EOF
    systemctl restart systemd-resolved
fi

echo -e "  ${VERDE}[OK] DNS configurado apuntando a $SERVIDOR_IP${RESET}"

# --- Verificar resolucion del dominio ---
echo ""
echo -e "  ${AMARILLO}Verificando resolucion del dominio $DOMINIO...${RESET}"
sleep 2

if ! host $DOMINIO &>/dev/null; then
    echo -e "  ${ROJO}[ERROR] No se puede resolver $DOMINIO${RESET}"
    echo -e "  ${AMARILLO}Verifica que el DNS del servidor AD este funcionando.${RESET}"
    echo ""
    exit 1
fi
echo -e "  ${VERDE}[OK] Dominio $DOMINIO resuelto correctamente.${RESET}"

# --- Instalar dependencias ---
echo ""
echo -e "  ${AMARILLO}Instalando dependencias (realmd, sssd, adcli)...${RESET}"
echo -e "  ${BLANCO}Esto puede tardar unos minutos...${RESET}"
echo ""

apt-get update -qq

PAQUETES="realmd sssd sssd-tools adcli samba-common-bin oddjob oddjob-mkhomedir packagekit"

for paquete in $PAQUETES; do
    if dpkg -l | grep -q "^ii  $paquete "; then
        echo -e "  ${AMARILLO}[OK] $paquete ya esta instalado.${RESET}"
    else
        echo -e "  ${CYAN}Instalando $paquete...${RESET}"
        apt-get install -y -qq $paquete
        if [ $? -eq 0 ]; then
            echo -e "  ${VERDE}[INSTALADO] $paquete${RESET}"
        else
            echo -e "  ${ROJO}[ERROR] Fallo al instalar $paquete${RESET}"
        fi
    fi
done

# --- Descubrir el dominio ---
echo ""
echo -e "  ${AMARILLO}Descubriendo el dominio $DOMINIO...${RESET}"

DISCOVER=$(realm discover $DOMINIO 2>&1)
if echo "$DISCOVER" | grep -q "realm-name"; then
    echo -e "  ${VERDE}[OK] Dominio $DOMINIO descubierto correctamente.${RESET}"
else
    echo -e "  ${ROJO}[ERROR] No se pudo descubrir el dominio:${RESET}"
    echo "$DISCOVER"
    echo ""
    exit 1
fi

# --- Confirmar y pedir contrasena ---
echo ""
echo -e "  ${BLANCO}Se unira esta maquina al dominio $DOMINIO.${RESET}"
echo -e "  ${BLANCO}Se necesita la contrasena del Administrador del dominio.${RESET}"
echo ""
read -p "  Deseas continuar? (s/n): " CONFIRMAR
if [ "$CONFIRMAR" != "s" ]; then
    echo ""
    echo -e "  ${AMARILLO}Operacion cancelada.${RESET}"
    echo ""
    exit 0
fi

echo ""
echo -e "  ${AMARILLO}Uniendo al dominio $DOMINIO...${RESET}"
echo -e "  ${BLANCO}(Se pedira la contrasena del Administrador)${RESET}"
echo ""

# Unir al dominio con realm
realm join --user=Administrator $DOMINIO

if [ $? -ne 0 ]; then
    echo ""
    echo -e "  ${ROJO}[ERROR] No se pudo unir al dominio.${RESET}"
    echo -e "  ${AMARILLO}Causas comunes:${RESET}"
    echo -e "  ${AMARILLO}  - Contrasena incorrecta${RESET}"
    echo -e "  ${AMARILLO}  - El servidor no esta disponible${RESET}"
    echo -e "  ${AMARILLO}  - El DNS no apunta al servidor AD${RESET}"
    echo ""
    exit 1
fi

echo ""
echo -e "  ${VERDE}[OK] Maquina unida al dominio $DOMINIO.${RESET}"

# --- Configurar sssd.conf ---
echo ""
echo -e "  ${AMARILLO}Configurando sssd.conf...${RESET}"

cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = $DOMINIO
config_file_version = 2
services = nss, pam

[domain/$DOMINIO]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $DOMINIO_UPPER
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = $DOMINIO
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf
echo -e "  ${VERDE}[OK] sssd.conf configurado (fallback_homedir = /home/%u@%d).${RESET}"

# --- Configurar creacion automatica de carpeta home ---
echo ""
echo -e "  ${AMARILLO}Configurando creacion automatica de carpeta home...${RESET}"

pam-auth-update --enable mkhomedir 2>/dev/null || true
echo -e "  ${VERDE}[OK] mkhomedir habilitado.${RESET}"

# --- Configurar sudo para usuarios de AD ---
echo ""
echo -e "  ${AMARILLO}Configurando permisos sudo para usuarios de AD...${RESET}"

mkdir -p /etc/sudoers.d/

cat > /etc/sudoers.d/ad-admins << EOF
# Permisos sudo para usuarios del dominio practica8.local
# Generado por unir_linux.sh

# Todos los usuarios del dominio pueden usar sudo
%domain\ admins@$DOMINIO ALL=(ALL) ALL
EOF

chmod 440 /etc/sudoers.d/ad-admins
echo -e "  ${VERDE}[OK] /etc/sudoers.d/ad-admins configurado.${RESET}"

# --- Reiniciar servicios ---
echo ""
echo -e "  ${AMARILLO}Reiniciando servicios sssd y oddjobd...${RESET}"

systemctl restart sssd
systemctl enable sssd
systemctl restart oddjobd 2>/dev/null || true
systemctl enable oddjobd 2>/dev/null || true

echo -e "  ${VERDE}[OK] Servicios reiniciados.${RESET}"

# --- Resumen final ---
echo ""
echo -e "  ${CYAN}+==========================================+${RESET}"
echo -e "  ${CYAN}| Union al dominio completada.             |${RESET}"
echo -e "  ${CYAN}+------------------------------------------+${RESET}"
echo -e "  ${VERDE}| Dominio   : $DOMINIO${RESET}"
echo -e "  ${VERDE}| Home dir  : /home/%u@%d                  |${RESET}"
echo -e "  ${VERDE}| Sudo      : Domain Admins habilitado     |${RESET}"
echo -e "  ${CYAN}+------------------------------------------+${RESET}"
echo -e "  ${AMARILLO}| Para iniciar sesion con un usuario AD:   |${RESET}"
echo -e "  ${AMARILLO}| usuario@practica8.local                  |${RESET}"
echo -e "  ${CYAN}+==========================================+${RESET}"
echo ""
