clear-host

write-host "-----------------------"
write-host "--Estado Del Servidor--"
write-host "-----------------------"

$hostname=hostname
write-host "Nombre del servidor: $hostname"

$ip=Get-NetIPAddress -InterfaceIndex 5 -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress
$ip2=Get-NetIPAddress -InterfaceIndex 7 -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress
write-host "Direccion IP NAT: $ip"
write-host "Direccion IP LAN: $ip2"

$almacenamiento=get-volume -driveletter C
$libre=[math]::Round($almacenamiento.SizeRemaining / 1GB, 2)
write-host "Espacio en disco: $libre"