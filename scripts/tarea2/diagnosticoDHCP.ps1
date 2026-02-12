function diagnostico-DHCP {
	param($scopeId)
	Write-Host "--------------------"
	Write-Host "-- Monitoreo DHCP --"
	Write-Host "--------------------"

	Write-Host "Estado del servidor: " ; Get-Service DhcpServer

	Write-Host "`nEquipos conectados Actulmente: "
	Get-DhcpServerv4Lease -ScopeId $scopeId | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime
}

#diagnostico-DHCP