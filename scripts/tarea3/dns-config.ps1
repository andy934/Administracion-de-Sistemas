Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   AUTOMATIZACION DE SERVIDOR DNS - WINDOWS SERVER" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "-- 1. Instalar Rol de DNS                              --"
Write-Host "-- 2. Configurar Zona Directa (Forward Zone)           --"
Write-Host "-- 3. Agregar Registro A (Nombre a IP)                 --"
Write-Host "-- 4. Eliminar Dominio                                 --"
Write-Host "-- 5. Ver Estado del Servidor                          --"
Write-Host "-- 6. Salir                                            --"
Write-Host "==========================================================" -ForegroundColor Cyan

$op = Read-Host "Seleccione una opcion"

switch ($op) {
    1 {
        Write-Host "[INSTALANDO] Rol de DNS..." -ForegroundColor Yellow
        Install-WindowsFeature DNS -IncludeManagementTools
        Write-Host "[OK] DNS instalado correctamente." -ForegroundColor Green
    }

    2 {
        Write-Host "`n=== CONFIGURACION DE ZONA DIRECTA ==="
        $dominio = Read-Host "Nombre del dominio (ej. reprobados.com)"
        $ip_destino = Read-Host "IP a la que resolverá el dominio (ej. 192.168.100.10)"

        Write-Host "[INFO] Creando zona primaria..." -ForegroundColor Blue
        # Uso del cmdlet requerido para crear la zona
        Add-DnsServerPrimaryZone -Name $dominio -ReplicationScope "Forest" -ErrorAction SilentlyContinue
        
        Write-Host "[INFO] Agregando registro principal..." -ForegroundColor Blue
        # Uso del cmdlet requerido para agregar el registro A
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $dominio -IPv4Address $ip_destino
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $dominio -IPv4Address $ip_destino
        
        Write-Host "[OK] Zona $dominio configurada con éxito." -ForegroundColor Green
    }

    3 {
        Write-Host "`n=== AGREGAR REGISTRO DNS ==="
        $dominio = Read-Host "Nombre del dominio existente"
        $name = Read-Host "Nombre del host (ej. ftp, mail)"
        $ip = Read-Host "Direccion IP"

        Add-DnsServerResourceRecordA -Name $name -ZoneName $dominio -IPv4Address $ip
        Write-Host "[OK] Registro $name.$dominio -> $ip agregado." -ForegroundColor Green
    }

    4 {
        Write-Host "`n=== ELIMINAR DOMINIO ==="
        Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
        $dominio = Read-Host "Nombre del dominio a eliminar"
        
        Remove-DnsServerZone -Name $dominio -Force
        Write-Host "[OK] Dominio $dominio eliminado correctamente." -ForegroundColor Green
    }

    5 {
        Write-Host "`n=== ESTADO DEL SERVIDOR DNS ==="
        Get-Service DNS | Select-Object Status, Name, DisplayName
        Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false }
    }

    6 { exit }
    
    Default { Write-Host "[ERROR] Opcion no valida" -ForegroundColor Red }
}