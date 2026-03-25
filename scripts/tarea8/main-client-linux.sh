#!/usr/bin/env bash
# =============================================================================
# main-client-linux.sh - Unir Rocky Linux 9 al dominio reprobados.com
# Practica 8 - Administracion de Sistemas
# =============================================================================

DOMAIN="reprobados.com"
DOMAIN_UPPER="REPROBADOS.COM"
DOMAIN_SHORT="REPROBADOS"
ADMIN_USER="Administrador"
DC_IP=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# VERIFICAR ROOT
# =============================================================================

if [ "$EUID" -ne 0 ]; then
    err "Ejecutar como root: sudo bash main-client-linux.sh"
    exit 1
fi

# =============================================================================
# VERIFICAR SI YA ESTA EN EL DOMINIO
# =============================================================================

en_dominio() {
    realm list 2>/dev/null | grep -q "reprobados.com"
    return $?
}

# =============================================================================
# INSTALAR PREREQUISITOS
# =============================================================================

instalar_prerequisitos() {
    info "Instalando paquetes necesarios para union al dominio..."

    dnf install -y \
        realmd \
        sssd \
        sssd-tools \
        sssd-ad \
        adcli \
        oddjob \
        oddjob-mkhomedir \
        samba-common-tools \
        krb5-workstation \
        openldap-clients \
        &>/dev/null

    if [ $? -eq 0 ]; then
        ok "Paquetes instalados: realmd, sssd, adcli, krb5"
    else
        err "Error instalando paquetes"
        return 1
    fi
}

# =============================================================================
# CONFIGURAR DNS PARA APUNTAR AL DC
# =============================================================================

configurar_dns() {
    local dc_ip="$1"
    info "Configurando DNS para apuntar al DC ($dc_ip)..."

    # Detectar interfaz activa
    local iface
    iface=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -z "$iface" ]; then
        warn "No se pudo detectar interfaz de red"
        return 1
    fi

    # Configurar DNS con nmcli
    nmcli con mod "$iface" ipv4.dns "$dc_ip 8.8.8.8" &>/dev/null || \
    nmcli con mod "$(nmcli -t -f NAME con show --active | head -1)" \
        ipv4.dns "$dc_ip 8.8.8.8" &>/dev/null

    nmcli con up "$iface" &>/dev/null || true

    # Tambien escribir en resolv.conf como respaldo
    cat > /etc/resolv.conf <<EOF
# Generado por main-client-linux.sh - Practica 8
search $DOMAIN
nameserver $dc_ip
nameserver 8.8.8.8
EOF

    # Evitar que NetworkManager sobreescriba resolv.conf
    echo -e "[main]\ndns=none" > /etc/NetworkManager/conf.d/no-dns.conf
    systemctl reload NetworkManager &>/dev/null || true

    ok "DNS configurado: primario=$dc_ip"
}

# =============================================================================
# VERIFICAR CONECTIVIDAD CON EL DC
# =============================================================================

verificar_conectividad() {
    local dc_ip="$1"
    info "Verificando conectividad con el DC ($dc_ip)..."

    if ping -c 2 -W 3 "$dc_ip" &>/dev/null; then
        ok "DC accesible: $dc_ip"
        return 0
    else
        err "No se puede alcanzar el DC: $dc_ip"
        err "Verifica que el servidor este activo y en la misma red"
        return 1
    fi
}

# =============================================================================
# CONFIGURAR HOSTNAME
# =============================================================================

configurar_hostname() {
    local hostname_actual
    hostname_actual=$(hostname)
    info "Hostname actual: $hostname_actual"

    read -rp "  Nuevo hostname (ENTER para mantener '$hostname_actual'): " nuevo
    if [ -n "$nuevo" ]; then
        hostnamectl set-hostname "$nuevo"
        ok "Hostname cambiado a: $nuevo"
    fi
}

# =============================================================================
# UNIR AL DOMINIO CON REALM
# =============================================================================

unir_dominio() {
    info "Uniendo al dominio $DOMAIN..."

    # Descubrir el dominio
    info "Descubriendo dominio..."
    realm discover "$DOMAIN" 2>/dev/null
    if [ $? -ne 0 ]; then
        warn "No se pudo descubrir el dominio automaticamente"
        warn "Continuando con union forzada..."
    fi

    # Unirse al dominio
    echo ""
    info "Ingresa la contrasena del Administrador del dominio:"
    realm join --user="$ADMIN_USER" "$DOMAIN"

    if [ $? -eq 0 ]; then
        ok "Equipo unido exitosamente al dominio $DOMAIN"
        return 0
    else
        err "Error al unirse al dominio"
        err "Verifica las credenciales y conectividad con el DC"
        return 1
    fi
}

# =============================================================================
# CONFIGURAR SSSD
# =============================================================================

configurar_sssd() {
    info "Configurando SSSD..."

    cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $DOMAIN
config_file_version = 2
services = nss, pam

[domain/$DOMAIN]
ad_domain = $DOMAIN
krb5_realm = $DOMAIN_UPPER
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u@%d
access_provider = ad
ad_gpo_access_control = disabled
EOF

    chmod 600 /etc/sssd/sssd.conf
    ok "sssd.conf configurado"
    ok "  fallback_homedir = /home/%u@%d"

    # Reiniciar SSSD
    systemctl enable --now sssd
    systemctl restart sssd

    if systemctl is-active sssd &>/dev/null; then
        ok "SSSD activo y corriendo"
    else
        err "SSSD no pudo iniciarse"
        journalctl -u sssd -n 10 --no-pager 2>/dev/null
    fi
}

# =============================================================================
# CONFIGURAR CREACION AUTOMATICA DE DIRECTORIOS HOME
# =============================================================================

configurar_homedir() {
    info "Configurando creacion automatica de directorios home..."

    # Habilitar oddjobd para crear home dirs automaticamente
    systemctl enable --now oddjobd &>/dev/null

    # Configurar PAM para crear home dir al login
    authselect select sssd with-mkhomedir --force &>/dev/null || \
    pam-auth-update --enable mkhomedir &>/dev/null || true

    # Alternativamente, editar PAM manualmente
    if ! grep -q "pam_mkhomedir" /etc/pam.d/system-auth 2>/dev/null; then
        sed -i '/^session.*pam_unix/a session     optional      pam_mkhomedir.so skel=/etc/skel/ umask=0022' \
            /etc/pam.d/system-auth 2>/dev/null || true
    fi

    ok "Creacion automatica de home dirs configurada"
    ok "  Ruta: /home/%u@%d"
}

# =============================================================================
# CONFIGURAR SUDO PARA USUARIOS DE AD
# =============================================================================

configurar_sudo() {
    info "Configurando sudo para usuarios del dominio AD..."

    # Crear archivo en sudoers.d para usuarios del dominio
    cat > /etc/sudoers.d/ad-admins <<EOF
# Practica 8 - Sudo para usuarios de Active Directory
# Permite a todos los usuarios del dominio usar sudo
# Modifica segun sea necesario para restringir por grupo

# Todos los usuarios autenticados del dominio
%$DOMAIN_SHORT\\\\domain\ admins ALL=(ALL) ALL

# Usuarios del grupo Cuates pueden usar sudo sin contrasena
%GrupoCuates@$DOMAIN ALL=(ALL) NOPASSWD: ALL
EOF

    chmod 440 /etc/sudoers.d/ad-admins
    ok "Archivo /etc/sudoers.d/ad-admins creado"
    ok "  GrupoCuates@$DOMAIN: sudo sin contrasena"
}

# =============================================================================
# CONFIGURAR FIREWALL
# =============================================================================

configurar_firewall() {
    info "Configurando firewall para comunicacion con AD..."
    firewall-cmd --permanent --add-service=kerberos &>/dev/null
    firewall-cmd --permanent --add-service=ldap     &>/dev/null
    firewall-cmd --permanent --add-service=ldaps    &>/dev/null
    firewall-cmd --reload &>/dev/null
    ok "Puertos Kerberos/LDAP abiertos en firewall"
}

# =============================================================================
# VERIFICAR UNION AL DOMINIO
# =============================================================================

verificar_union() {
    info "Verificando union al dominio..."
    echo ""

    # Verificar realm
    local realm_info
    realm_info=$(realm list 2>/dev/null)
    if echo "$realm_info" | grep -q "$DOMAIN"; then
        ok "Dominio detectado: $DOMAIN"
        echo "$realm_info" | grep -E "domain-name|configured|server-software" | \
            sed 's/^/      /'
    else
        err "El equipo no esta unido al dominio"
        return 1
    fi

    # Verificar que se pueden resolver usuarios
    echo ""
    info "Probando resolucion de usuarios del dominio..."
    if id "Administrador@$DOMAIN" &>/dev/null; then
        ok "Usuario Administrador@$DOMAIN resuelto correctamente"
    else
        warn "No se pudo resolver Administrador@$DOMAIN"
        warn "SSSD puede necesitar tiempo para sincronizar"
    fi

    echo ""
    ok "Union al dominio verificada"
}

# =============================================================================
# FLUJO PRINCIPAL
# =============================================================================

echo ""
echo -e "${CYAN}  +========================================================+${NC}"
echo -e "${CYAN}  |   UNION AL DOMINIO reprobados.com                      |${NC}"
echo -e "${CYAN}  |   Cliente Rocky Linux 9                                 |${NC}"
echo -e "${CYAN}  +========================================================+${NC}"
echo ""

if en_dominio; then
    info "Este equipo ya esta unido al dominio $DOMAIN"
    realm list
    exit 0
fi

# Solicitar IP del DC
echo ""
while [ -z "$DC_IP" ]; do
    read -rp "  IP del servidor DC (ej. 192.168.1.10): " DC_IP
done

# Ejecutar pasos
instalar_prerequisitos || exit 1
configurar_dns "$DC_IP"
verificar_conectividad "$DC_IP" || exit 1
configurar_hostname
configurar_firewall
unir_dominio || exit 1
configurar_sssd
configurar_homedir
configurar_sudo
verificar_union

echo ""
ok "Proceso completado. El cliente Linux esta unido al dominio $DOMAIN"
info "Los usuarios del AD pueden iniciar sesion con: usuario@$DOMAIN"
info "O simplemente: usuario (si use_fully_qualified_names = False)"
