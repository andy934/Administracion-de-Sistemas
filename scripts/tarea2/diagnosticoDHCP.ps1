function diagnostico-DHCP {
	Write-Host "--------------------"
	Write-Host "-- Monitoreo DHCP --"
	Write-Host "--------------------"

	Write-Host "Estado del servidor: " ; Get-Service DhcpServer

	Write-Host "`nEquipos conectados Actulmente: "
	Get-DhcpServerv4Lease -ScopeId 192.168.100.0 | Select-Object IPAddress, ClienteId, HostName, LeaseExpiryTime
}

diagnostico-DHCP