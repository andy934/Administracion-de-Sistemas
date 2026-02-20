Write-Host "=========================================================="
Write-Host "==   AUTOMATIZACION DE SERVIDOR DNS - WINDOWS SERVER    ==" 
Write-Host "=========================================================="
Write-Host "-- 1. Instalar Rol de DNS                              --"
Write-Host "-- 2. Configurar Zona Directa (Forward Zone)           --"
Write-Host "-- 3. Agregar Registro A (Nombre a IP)                 --"
Write-Host "-- 4. Eliminar Dominio                                 --"
Write-Host "-- 5. Ver Estado del Servidor                          --"
Write-Host "-- 6. Salir                                            --"
Write-Host "=========================================================="

$op = Read-Host "Seleccione una opcion"

switch ($op) {
    1 {
        Write-Host "[INSTALANDO] Rol de DNS..." 
        Install-WindowsFeature DNS -IncludeManagementTools
        Write-Host "[OK] DNS instalado correctamente." n
    }

    2 {
        Write-Host "`n=== CONFIGURACION DE ZONA DIRECTA ==="
        $dominio = Read-Host "Nombre del dominio (ej. reprobados.com)"
        $ip_destino = Read-Host "IP a la que resolverá el dominio (ej. 192.168.100.1)"

        Write-Host "[INFO] Creando zona primaria local..."
        # Eliminamos -ReplicationScope y agregamos -ZoneFile para modo local
        Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns" -ErrorAction Stop
        
        Write-Host "[INFO] Agregando registros A..." 
        # Cmdlets requeridos por la actividad
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $dominio -IPv4Address $ip_destino
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $dominio -IPv4Address $ip_destino
        
        Write-Host "[OK] Zona $dominio configurada correctamente." 
    }

    3 {
        Write-Host "`n=== AGREGAR REGISTRO DNS ==="
        $dominio = Read-Host "Nombre del dominio existente"
        $name = Read-Host "Nombre del host (ej. ftp, mail)"
        $ip = Read-Host "Direccion IP"

        Add-DnsServerResourceRecordA -Name $name -ZoneName $dominio -IPv4Address $ip
        Write-Host "[OK] Registro $name.$dominio -> $ip agregado."
    }

    4 {
        Write-Host "`n=== ELIMINAR DOMINIO ==="
        Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
        $dominio = Read-Host "Nombre del dominio a eliminar"
        
        Remove-DnsServerZone -Name $dominio -Force
        Write-Host "[OK] Dominio $dominio eliminado correctamente."
    }

    5 {
        Write-Host "`n=== ESTADO DEL SERVIDOR DNS ==="
        Get-Service DNS | Select-Object Status, Name, DisplayName
        Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false }
    }

    6 { exit }
    
    Default { Write-Host "[ERROR] Opcion no valida" -ForegroundColor Red }
}