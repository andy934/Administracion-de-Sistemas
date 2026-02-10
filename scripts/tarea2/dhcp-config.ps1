. .\validadorIPv4.ps1
. .\diagnosticoDHCP.ps1
#$res = Validar-IP -uIP $initIP

Write-Host "---------------------------------------------------"
Write-Host "-- Opcines.                                      --"
Write-Host "-- 1. Instalar Servidor                          --"
Write-Host "-- 2. Configuracion                              --"
Write-Host "-- 3. Lista de Concesiones y Estado del Servidor --"
Write-Host "-- 4. Salir                                      --"
Write-Host "---------------------------------------------------"

$op = Read-Host "Eliga una opcion: "

switch ($op) {
	1 {
		$dhcpInstall = (Get-WindowsFeature DHCP).installed

		$op = Read-Host "SI HACE OTRA CONFIGURACION EL ARCHIVO ACTUAL SE BORRARA. Continuar (s/n)"
		if ($op -ieq 'n'){
			Write-Host "Operacion Cancelada por el usuario"
			exit 0
		}

		Remove-DhcpServerv4Scope -ScopeId 192.168.100.0 -Force
		if ( -not $dhcpInstall){
			Install-WindowsFeature -Name DHCP -IncludeManagementTools
			Restart-Service DhcpServer
		}
	}

	2 {
		$scope = Read-Host "Nombre descriptivo: "
		$initIP = Read-Host "Rango inicial de direcciones IPv4: "
		$res = Validar-IP -uIP $initIP
		if ( $res -eq 1){
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		$finIP = Read-Host "Rango final de direcciones IPv4: "
		$res = Validar-IP -uIP $initIP
		if ( $res -eq 1){
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		$routerIP = Read-Host "Ingrese la IPv4 del Router/Gateway: "
		$res = Validar-IP -uIP $initIP
		if ( $res -eq 1){
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		$dnsIP = Read-Host "Ingrese al IPv4 del DNS: "
		$res = Validar-IP -uIP $initIP
		if ( $res -eq 1){
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		$timepo = Read-Host "Tiempo de concesion (dias.horas:minutos:segundos): "

		#Proceso de aplicar la configuracion
		$mask = "255.255.255.0"
		Add-DhcpServerv4Scope -Name $scope -StartRange $initIP -EndRange $finIP -SubnetMask $mask -LeaseDuration $timepo -State Active | Out-Null

		Set-DhcpServerv4OptionValue -ScopeId $initIP -Router $routerIP -DnsServer $dnsIP -Force | Out-Null

		New-NetFirewallRule -DisplayName "DHCP-Servicio" -Direction Inbound -Protocol UDP -LocalPort 67,68 -Action Allow | Out-Null

		Write-Host "Ambito configurado cerrectamente..."
	}

	3 { diagnostico-DHCP }

	4 { exit 0 }

	default { Write-Host "No es una opcion valida..." }
}