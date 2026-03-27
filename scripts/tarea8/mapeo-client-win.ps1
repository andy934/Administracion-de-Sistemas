# 1. Detectar quién inició sesión automáticamente
$usuarioActual = $env:USERNAME
$SERVER_IP = "192.168.137.130"

# 2. Construir la ruta dinámica
$SHARE_NAME = "Z_$usuarioActual"
$SHARE_PATH = "\\$SERVER_IP\$SHARE_NAME"

Write-Host "Configurando unidad de red para el usuario: $usuarioActual..."

# 3. Intentar el mapeo
net use Z: $SHARE_PATH /persistent:yes