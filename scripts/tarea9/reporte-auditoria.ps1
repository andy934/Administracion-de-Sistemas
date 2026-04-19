# =============================================================================
# reporte-auditoria.ps1 - Script de extraccion de eventos de seguridad
# Practica 9 - Administrador: admin_auditoria puede ejecutar este script
# Sistema: Windows Server 2022
# Uso: .\reporte-auditoria.ps1 [-MaxEventos 10] [-RutaSalida "C:\reporte.txt"]
# =============================================================================

param(
    [int]$MaxEventos   = 10,
    [string]$RutaSalida = "C:\Auditoria\reporte-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$salida    = @()

function Linea { param($texto) $salida += $texto; Write-Host $texto }
function Sep   { Linea ("-" * 65) }
function Sep2  { Linea ("=" * 65) }

Sep2
Linea "  REPORTE DE AUDITORIA DE SEGURIDAD - PRACTICA 9"
Linea "  Dominio  : reprobados.com"
Linea "  Servidor : $env:COMPUTERNAME"
Linea "  Generado : $timestamp"
Linea "  Ejecutado por: $env:USERNAME"
Sep2
Linea ""

# =============================================================================
# SECCION 1: INICIOS DE SESION FALLIDOS (4625)
# =============================================================================

Sep
Linea "  SECCION 1: INICIOS DE SESION FALLIDOS (Evento ID: 4625)"
Sep
Linea ""

try {
    $ev4625 = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } `
        -MaxEvents $MaxEventos -ErrorAction Stop

    Linea "  Total encontrados: $($ev4625.Count) (mostrando maximo $MaxEventos)"
    Linea ""

    $i = 1
    foreach ($ev in $ev4625) {
        $xml = [xml]$ev.ToXml()
        $ns  = @{ e = 'http://schemas.microsoft.com/win/2004/08/events/event' }

        $usuario   = ($xml.SelectNodes("//e:Data[@Name='TargetUserName']",$ns) | Select-Object -First 1).'#text'
        $dominio   = ($xml.SelectNodes("//e:Data[@Name='TargetDomainName']",$ns) | Select-Object -First 1).'#text'
        $ip        = ($xml.SelectNodes("//e:Data[@Name='IpAddress']",$ns) | Select-Object -First 1).'#text'
        $logonType = ($xml.SelectNodes("//e:Data[@Name='LogonType']",$ns) | Select-Object -First 1).'#text'
        $subStatus = ($xml.SelectNodes("//e:Data[@Name='SubStatus']",$ns) | Select-Object -First 1).'#text'
        $proceso   = ($xml.SelectNodes("//e:Data[@Name='ProcessName']",$ns) | Select-Object -First 1).'#text'

        # Decodificar SubStatus
        $razon = switch ($subStatus) {
            "0xC000006A" { "Contrasena incorrecta" }
            "0xC0000064" { "Usuario no existe" }
            "0xC0000234" { "Cuenta bloqueada" }
            "0xC0000072" { "Cuenta deshabilitada" }
            "0xC000006F" { "Hora de inicio de sesion no permitida" }
            "0xC0000070" { "Estacion de trabajo no permitida" }
            "0xC0000071" { "Contrasena expirada" }
            default       { "SubStatus: $subStatus" }
        }

        Linea "  [$i] Fecha/Hora  : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
        Linea "      Usuario     : $dominio\$usuario"
        Linea "      IP Origen   : $ip"
        Linea "      Tipo Logon  : $logonType"
        Linea "      Razon       : $razon"
        Linea "      Proceso     : $proceso"
        Linea ""
        $i++
    }
} catch {
    Linea "  No se pudieron leer eventos 4625: $($_.Exception.Message)"
    Linea "  Verifica que el log de Seguridad este habilitado y tengas permisos."
    Linea ""
}

# =============================================================================
# SECCION 2: CUENTAS BLOQUEADAS (4740)
# =============================================================================

Sep
Linea "  SECCION 2: CUENTAS BLOQUEADAS (Evento ID: 4740)"
Sep
Linea ""

try {
    $ev4740 = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4740 } `
        -MaxEvents 10 -ErrorAction Stop

    Linea "  Total encontrados: $($ev4740.Count)"
    Linea ""

    foreach ($ev in $ev4740) {
        Linea "  Fecha/Hora : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
        Linea "  Mensaje    : $($ev.Message.Split([Environment]::NewLine)[0])"
        Linea ""
    }
} catch {
    Linea "  No se encontraron eventos 4740 recientes."
    Linea ""
}

# =============================================================================
# SECCION 3: CAMBIOS EN CUENTAS DE USUARIO (4720, 4722, 4723, 4724, 4725)
# =============================================================================

Sep
Linea "  SECCION 3: CAMBIOS EN CUENTAS (4720/4722/4724/4725)"
Sep
Linea ""

try {
    $evCuentas = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id      = @(4720, 4722, 4723, 4724, 4725, 4726)
    } -MaxEvents 10 -ErrorAction Stop

    foreach ($ev in $evCuentas) {
        $tipo = switch ($ev.Id) {
            4720 { "Cuenta CREADA" }
            4722 { "Cuenta HABILITADA" }
            4723 { "Cambio de CONTRASENA" }
            4724 { "RESET de contrasena" }
            4725 { "Cuenta DESHABILITADA" }
            4726 { "Cuenta ELIMINADA" }
        }
        Linea "  $tipo - $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
    }
    Linea ""
} catch {
    Linea "  No se encontraron eventos de cambio de cuentas recientes."
    Linea ""
}

# =============================================================================
# SECCION 4: ESTADO ACTUAL DE CUENTAS BLOQUEADAS EN AD
# =============================================================================

Sep
Linea "  SECCION 4: CUENTAS BLOQUEADAS ACTUALMENTE EN AD"
Sep
Linea ""

try {
    $bloqueadas = Search-ADAccount -LockedOut -ErrorAction Stop
    if ($bloqueadas) {
        Linea "  ATENCION: Hay $($bloqueadas.Count) cuenta(s) bloqueada(s):"
        foreach ($c in $bloqueadas) {
            Linea "    - $($c.SamAccountName) | $($c.DistinguishedName)"
        }
    } else {
        Linea "  No hay cuentas bloqueadas en este momento."
    }
    Linea ""
} catch {
    Linea "  Error consultando AD: $($_.Exception.Message)"
    Linea ""
}

Sep2
Linea "  FIN DEL REPORTE - $timestamp"
Sep2

# Guardar a archivo
$dir = Split-Path $RutaSalida -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$salida | Set-Content -Path $RutaSalida -Encoding UTF8
Write-Host ""
Write-Host "[OK] Reporte guardado en: $RutaSalida" -ForegroundColor Green
