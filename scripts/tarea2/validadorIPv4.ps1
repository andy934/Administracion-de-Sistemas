function Validar-IP {
	param($uIP)
	
	$regla = '^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$'
	
	if ( $uIP -match $regla) {
		$res = 0
	}
	else {
		$res = 1
	}
	
	return $res		
}

function calcular-mascara {
	param ($segmentoIP)

	$primer_octeto = ($segmentoIP -split '\.')[0]
	
	if ($primer_octeto -ge 1 -and $primer_octeto -le 126 ) {
		$mask = "255.0.0.0"
		$cidr = 8
	}
	elseif ( $primer_octeto -ge 128 -and $primer_octeto -le 191 ) {
		$mask = "255.255.0.0"
		$cidr = 16
	}
	else {
		$mask = "255.255.255.0"
		$cidr = 24
	}

	# Devolvemos un objeto con ambos valores
	return [PSCustomObject]@{
		Mask = $mask
		CIDR = $cidr
	}
}
<#
$uIP = Read-Host "IP: "

$res = Validar-IP -uIP $uIP

if ( $res -eq 0){
	Write-Host "Su ip es IPv4"
}else{
	Write-Host "Su ip no es IPv4"
}
#>