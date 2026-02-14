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

$op = Read-Host "Elija una opcion: "

switch ($op) {
	1 {
		$dhcpInstall = (Get-WindowsFeature DHCP).installed
		
		if ( -not $dhcpInstall) {
			Install-WindowsFeature -Name DHCP -IncludeManagementTools
			Restart-Service DhcpServer
		}
	}

	2 {
		#Verificar si ya existe un scope con ese Id, si lo hay eliminarlo
		$op = Read-Host "Ya tienes un scope con ese Id, si continuas el scope que ya tenias se BORRARA. Continuar (s/n)"
		if ($op -ieq 'n') {
			Write-Host "Operacion Cancelada por el usuario"
			exit 0
		}
		
		$scope = Read-Host "Nombre descriptivo: "
		
		$segmentoIP = Read-Host "Ingrese el segmento de red: "
		$res = validar-IP -uIP $segmentoIP
		if ( $res -eq 1) {
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		$resultado_mascara = calcular-mascara -segmentoIP $segmentoIP
		$cidr = $resultado_mascara.CIDR
		$mascara = $resultado_mascara.Mask
		$segmento_base = ($segmentoIP -split '\.')[0..2] -join '.'

		$interfaceName = "Ethernet1"
		Get-NetIPAddress -InterfaceAlias $interfaceName -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
		
		try {
			New-NetIPAddress -InterfaceAlias $interfaceName -IPAddress "$segmento_base.1" -PrefixLength $cidr -ErrorAction Stop | Out-Null
		}
		catch {
			# Si la IP ya existe, la actualizamos
			Set-NetIPAddress -InterfaceAlias $interfaceName -IPAddress "$segmento_base.1" -PrefixLength $cidr | Out-Null
		}

		#Calculamos el ID de Red Real según la clase
		$octetos = $segmentoIP.Split('.')
		if ($mascara -eq "255.0.0.0") {
			$idRedReal = "$($octetos[0]).0.0.0" # Clase A
		}
		elseif ($mascara -eq "255.255.0.0") {
			$idRedReal = "$($octetos[0]).$($octetos[1]).0.0" # Clase B
		}
		else {
			$idRedReal = "$($octetos[0]).$($octetos[1]).$($octetos[2]).0" # Clase C
		}

		$scopeExist = Get-DhcpServerv4Scope -ScopeId $idRedReal -ErrorAction SilentlyContinue
		if ($scopeExist) {
			Write-Host "Detectado ámbito previo en $idRedReal. Eliminando para evitar conflictos..." -ForegroundColor Yellow
			Remove-DhcpServerv4Scope -ScopeId $idRedReal -Force | Out-Null
		}

		$initIP = Read-Host "Rango inicial de direcciones IPv4: "
		$res = Validar-IP -uIP $initIP
		if ( $res -eq 1) {
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		$finIP = Read-Host "Rango final de direcciones IPv4: "
		$res = Validar-IP -uIP $finIP
		if ( $res -eq 1) {
			Write-Host "Error: La IP no cumple con el formato IPv4..."
			exit 1
		}

		#Validar que las ips pertenezcan al segmento de red
		$init_base = ($initIP -split '\.')[0..2] -join '.'
		$fin_base = ($finIP -split '\.')[0..2] -join '.'

		if (($init_base -ne $segmento_base) -or ($fin_base -ne $segmento_base)) {
			Write-Host "Error: Las IPs del rango no pertenecen al segmento $segmentoIP..."
			exit 1
		}

		$routerIP = Read-Host "Ingrese la IPv4 del Router/Gateway: "
		if ( -not [string]::IsNullOrEmpty($routerIP)) {
			$res = Validar-IP -uIP $routerIP
			if ( $res -eq 1) {
				Write-Host "Error: La IP no cumple con el formato IPv4..."
				exit 1
			}
		}

		$dnsIP = Read-Host "Ingrese al IPv4 del DNS: "
		if ( -not [string]::IsNullOrEmpty($dnsIP)) {
			$res = Validar-IP -uIP $dnsIP
			if ( $res -eq 1) {
				Write-Host "Error: La IP no cumple con el formato IPv4..."
				exit 1
			}
		}

		$tiempo = Read-Host "Tiempo de concesion (dias.horas:minutos:segundos): "

		#Proceso de aplicar la configuracion
		try {
			Add-DhcpServerv4Scope -Name $scope -StartRange $initIP -EndRange $finIP -SubnetMask $mascara -LeaseDuration $tiempo -State Active | Out-Null

			# Solo aplicamos opciones de Router/DNS si el usuario ingresó datos
			if (-not [string]::IsNullOrEmpty($routerIP)) {
				Set-DhcpServerv4OptionValue -ScopeId $segmentoIP -Router $routerIP -Force | Out-Null
			}
			if (-not [string]::IsNullOrEmpty($dnsIP)) {
				Set-DhcpServerv4OptionValue -ScopeId $segmentoIP -DnsServer $dnsIP -Force | Out-Null
			}
			#Verificar si la regla del firewall ya existe
			$firewallRule = Get-NetFirewallRule -DisplayName "DHCP-Servicio" -ErrorAction SilentlyContinue
			if ( -not $firewallRule) {
				New-NetFirewallRule -DisplayName "DHCP-Servicio" -Direction Inbound -Protocol UDP -LocalPort 67, 68 -Action Allow | Out-Null
			}

			Restart-Service DhcpServer
		}
		catch {
			Write-Host "Error: Algo salio mal con la configuracion del servidor DHCP: $_"
			exit 1
		}
		
		Write-Host "Ambito configurado correctamente..."
	}

	3 { diagnostico-DHCP }

	4 { exit 0 }

	default { Write-Host "No es una opcion valida..." }
}