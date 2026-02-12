function diagnostico-DHCP {
	Write-Host "--------------------"
	Write-Host "-- Monitoreo DHCP --"
	Write-Host "--------------------"

	$servicio = Get-Service DhcpServer -ErrorAction SilentlyContinue
	Write-Host "Estado del servidor: $($servicio.Status)"
	
	$scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
	if ($null -eq $scopes) {
		Write-Host "No se encontraron ambitos configurados en el sistema."
	}
	else {
		foreach ($s in $scopes) {
			Write-Host "`n--- Ambito: $($s.Name) ($($s.ScopeId)) ---"
			# 3. Pedimos las concesiones de cada ambito encontrado
			$leases = Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue
            
			if ($null -ne $leases) {
				$leases | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | Format-Table -AutoSize
			}
			else {
				Write-Host "No hay equipos conectados en este ambito."
			}
		}
	}
}

#diagnostico-DHCP