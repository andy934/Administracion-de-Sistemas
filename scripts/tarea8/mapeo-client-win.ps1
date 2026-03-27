# Script para mapear la unidad personal
$SERVER_IP = "192.168.137.130" # Asegurate que sea la IP de tu Server Core
$LETRA     = "Z:"

Write-Host "Configurando unidad de red para $($env:USERNAME)..." -ForegroundColor Cyan

# Borramos si ya existe para evitar errores
if (Test-Path $LETRA) {
    net use $LETRA /delete /y | Out-Null
}

# Mapeo de la carpeta
# Nota: No requiere ejecutar como administrador
net use $LETRA "\\$SERVER_IP\Compartida" /persistent:yes

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Unidad $LETRA conectada correctamente." -ForegroundColor Green
    Write-Host "[INFO] Verificando cuota..." -ForegroundColor Yellow
    Get-PSDrive $LETRA[0] | Select-Object Name, @{n="GigabytesFree";e={$_.Free/1GB}}, @{n="UsedGB";e={$_.Used/1GB}}
} else {
    Write-Host "[ERROR] No se pudo conectar la unidad." -ForegroundColor Red
}