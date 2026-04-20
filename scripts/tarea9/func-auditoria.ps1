# =============================================================================
# func-auditoria.ps1 - FGPP, Auditoria de Eventos y Monitoreo
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# Sistema: Windows Server 2022
# =============================================================================

$DOMAIN_DN = "DC=reprobados,DC=local"
$REPORTE_PATH = "C:\Auditoria\reporte-accesos-denegados.txt"
$REPORTE_DIR = "C:\Auditoria"

# =============================================================================
# FINE-GRAINED PASSWORD POLICY (FGPP)
# =============================================================================

function Configurar-FGPP {
    if (-not (Validar-AD-P9)) { return }
    Write-Info "Configurando Fine-Grained Password Policies (FGPP)..."
    Write-Host ""

    # FGPP para administradores delegados (12 caracteres minimo)
    $fgppAdmin = "PSO-AdminsDelegados"
    if (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'" -ErrorAction SilentlyContinue) {
        Write-Info "FGPP '$fgppAdmin' ya existe"
    }
    else {
        New-ADFineGrainedPasswordPolicy `
            -Name                        $fgppAdmin `
            -Precedence                  10 `
            -MinPasswordLength           12 `
            -PasswordHistoryCount        10 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -MinPasswordAge              "1.00:00:00" `
            -MaxPasswordAge              "60.00:00:00" `
            -LockoutThreshold            5 `
            -LockoutDuration             "00:30:00" `
            -LockoutObservationWindow    "00:30:00" `
            -Description                 "P9 - Politica para administradores delegados (min 12 chars)"

        Write-OK "FGPP '$fgppAdmin' creada: minimo 12 caracteres"
    }

    # Aplicar FGPP a los 4 administradores delegados
    foreach ($admin in @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")) {
        try {
            Add-ADFineGrainedPasswordPolicySubject `
                -Identity $fgppAdmin -Subjects $admin -ErrorAction SilentlyContinue
            Write-OK "  FGPP admin aplicada a: $admin"
        }
        catch {
            Write-Warn "  $admin ya tiene FGPP o no existe"
        }
    }

    Write-Host ""

    # FGPP para usuarios estandar (8 caracteres minimo)
    $fgppUser = "PSO-UsuariosEstandar"
    if (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppUser'" -ErrorAction SilentlyContinue) {
        Write-Info "FGPP '$fgppUser' ya existe"
    }
    else {
        New-ADFineGrainedPasswordPolicy `
            -Name                        $fgppUser `
            -Precedence                  20 `
            -MinPasswordLength           8 `
            -PasswordHistoryCount        5 `
            -ComplexityEnabled           $true `
            -ReversibleEncryptionEnabled $false `
            -MinPasswordAge              "1.00:00:00" `
            -MaxPasswordAge              "90.00:00:00" `
            -LockoutThreshold            5 `
            -LockoutDuration             "00:30:00" `
            -LockoutObservationWindow    "00:30:00" `
            -Description                 "P9 - Politica para usuarios estandar (min 8 chars)"

        Write-OK "FGPP '$fgppUser' creada: minimo 8 caracteres"
    }

    # Aplicar a grupos de usuarios estandar
    foreach ($grupo in @("Cuates", "NoCuates")) {
        try {
            Add-ADFineGrainedPasswordPolicySubject `
                -Identity $fgppUser -Subjects $grupo -ErrorAction SilentlyContinue
            Write-OK "  FGPP usuario aplicada a grupo: $grupo"
        }
        catch {
            Write-Warn "  Grupo $grupo no encontrado o ya tiene FGPP"
        }
    }

    Write-Host ""
    Write-OK "Fine-Grained Password Policies configuradas"
    Write-Host ""
    Write-Host "  Resumen FGPP:" -ForegroundColor White
    Write-Host "    PSO-AdminsDelegados : minimo 12 caracteres (precedencia 10)"
    Write-Host "    PSO-UsuariosEstandar: minimo  8 caracteres (precedencia 20)"
}

# =============================================================================
# HARDENING DE AUDITORIA
# =============================================================================

function Configurar-Auditoria {
    Write-Info "Configurando politicas de auditoria (Hardening)..."
    Write-Host ""

    # Activamos por Categoría para evitar errores de acentos o traducciones
    auditpol /set /category:"Inicio/cierre de sesión" /success:enable /failure:enable | Out-Null
    auditpol /set /category:"Administración de cuentas" /success:enable /failure:enable | Out-Null
    auditpol /set /category:"Acceso de objetos" /success:enable /failure:enable | Out-Null
    
    Write-OK "Auditoria habilitada: Inicio/Cierre, Cuentas y Objetos"
    Write-Host ""

    # El resto de la función (creación y vinculación de la GPO) se queda igual
    $gpoName = "P9-Auditoria-Hardening"
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoName -Comment "P9 - Politicas de auditoria"
        Write-OK "GPO '$gpoName' creada"
    }

    Write-Host ""

    # Configurar via GPO tambien
    $gpoName = "P9-Auditoria-Hardening"
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoName -Comment "P9 - Politicas de auditoria"
        Write-OK "GPO '$gpoName' creada"
    }

    # Configurar auditoria en la GPO
    $auditSettings = @(
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "AuditBaseObjects"; Value = 1 },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "FullPrivilegeAuditing"; Value = 1 }
    )

    foreach ($s in $auditSettings) {
        Set-GPRegistryValue -Name $gpoName -Key $s.Key -ValueName $s.Name `
            -Type DWord -Value $s.Value -ErrorAction SilentlyContinue | Out-Null
    }

    # Vincular GPO al dominio
    $linked = (Get-GPInheritance -Target $DOMAIN_DN -ErrorAction SilentlyContinue).GpoLinks |
    Where-Object { $_.DisplayName -eq $gpoName }
    if (-not $linked) {
        New-GPLink -Name $gpoName -Target $DOMAIN_DN -LinkEnabled Yes -ErrorAction SilentlyContinue | Out-Null
        Write-OK "GPO de auditoria vinculada al dominio"
    }

    # Forzar actualizacion de politicas
    & gpupdate /force 2>&1 | Out-Null
    Write-OK "Politicas de auditoria actualizadas (gpupdate /force)"
    Write-Host ""
    Write-OK "Hardening de auditoria completado"
}

# =============================================================================
# SCRIPT DE MONITOREO: EXPORTAR EVENTOS 4625 (ACCESO DENEGADO)
# =============================================================================

function Generar-Reporte-Auditoria {
    param(
        [int]$MaxEventos = 10,
        [string]$RutaReporte = $REPORTE_PATH
    )

    Write-Info "Generando reporte de accesos denegados..."

    # Crear directorio si no existe
    if (-not (Test-Path $REPORTE_DIR)) {
        New-Item -ItemType Directory -Path $REPORTE_DIR -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $lineas = @()
    $lineas += "=" * 60
    $lineas += "REPORTE DE AUDITORIA DE SEGURIDAD"
    $lineas += "Practica 9 - reprobados.com"
    $lineas += "Generado: $timestamp"
    $lineas += "Servidor: $env:COMPUTERNAME"
    $lineas += "=" * 60
    $lineas += ""

    # Evento 4625: Inicio de sesion fallido
    Write-Info "  Buscando eventos 4625 (inicio de sesion fallido)..."
    $lineas += "INTENTOS DE INICIO DE SESION FALLIDOS (Evento 4625)"
    $lineas += "-" * 60

    try {
        $eventos4625 = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id      = 4625
        } -MaxEvents $MaxEventos -ErrorAction SilentlyContinue

        if ($eventos4625) {
            foreach ($ev in $eventos4625) {
                $xml = [xml]$ev.ToXml()
                $ns = @{ e = 'http://schemas.microsoft.com/win/2004/08/events/event' }
                $getData = { param($name) ($xml.SelectNodes("//e:Data[@Name='$name']", $ns) | Select-Object -First 1).'#text' }

                $usuario = & $getData "TargetUserName"
                $dominio = & $getData "TargetDomainName"
                $ip = & $getData "IpAddress"
                $tipoLogon = & $getData "LogonType"
                $razon = & $getData "FailureReason"
                $subStatus = & $getData "SubStatus"

                $lineas += "Fecha/Hora : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
                $lineas += "Usuario    : $dominio\$usuario"
                $lineas += "IP Origen  : $ip"
                $lineas += "Tipo Logon : $tipoLogon"
                $lineas += "SubStatus  : $subStatus"
                $lineas += "Descripcion: $($ev.Message -replace '\r?\n',' ' | Select-Object -First 1)"
                $lineas += ""
            }
            Write-OK "  $($eventos4625.Count) eventos 4625 encontrados"
        }
        else {
            $lineas += "No se encontraron eventos 4625 recientes."
            $lineas += ""
            Write-Warn "  No se encontraron eventos 4625"
        }
    }
    catch {
        $lineas += "Error al leer eventos: $($_.Exception.Message)"
        $lineas += ""
        Write-Warn "  Error leyendo eventos de seguridad: $_"
    }

    # Evento 4740: Cuenta bloqueada
    $lineas += "CUENTAS BLOQUEADAS (Evento 4740)"
    $lineas += "-" * 60

    try {
        $eventos4740 = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id      = 4740
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($eventos4740) {
            foreach ($ev in $eventos4740) {
                $lineas += "Fecha/Hora : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
                $lineas += "Evento     : $($ev.Message -replace '\r?\n',' ')"
                $lineas += ""
            }
            Write-OK "  $($eventos4740.Count) eventos 4740 encontrados"
        }
        else {
            $lineas += "No se encontraron cuentas bloqueadas recientemente."
            $lineas += ""
        }
    }
    catch { }

    # Evento 4648: Intento de logon con credenciales explicitas
    $lineas += "LOGON CON CREDENCIALES EXPLICITAS (Evento 4648)"
    $lineas += "-" * 60

    try {
        $eventos4648 = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id      = 4648
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($eventos4648) {
            foreach ($ev in $eventos4648) {
                $lineas += "Fecha/Hora : $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
                $lineas += "Mensaje    : $($ev.Message.Substring(0, [Math]::Min(200, $ev.Message.Length)))"
                $lineas += ""
            }
        }
        else {
            $lineas += "No se encontraron eventos 4648 recientes."
            $lineas += ""
        }
    }
    catch { }

    $lineas += "=" * 60
    $lineas += "FIN DEL REPORTE - $timestamp"
    $lineas += "=" * 60

    # Guardar reporte
    $lineas | Set-Content -Path $RutaReporte -Encoding UTF8
    Write-OK "Reporte guardado en: $RutaReporte"
    Write-Host ""
    Write-Host "  Primeras lineas del reporte:" -ForegroundColor Cyan
    Get-Content $RutaReporte | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
}

# =============================================================================
# VERIFICAR ESTADO DE AUDITORIA
# =============================================================================

function Mostrar-Estado-Auditoria {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DE AUDITORIA Y FGPP             " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Estado auditpol
    Write-Host "  Politicas de auditoria activas:" -ForegroundColor White
    & auditpol /get /category:"Logon/Logoff", "Object Access", "Account Management" 2>$null |
    Where-Object { $_ -match "Success|Failure|No Auditing" } |
    Select-Object -First 10 |
    ForEach-Object { Write-Host "    $_" }

    Write-Host ""
    Write-Host "  Fine-Grained Password Policies:" -ForegroundColor White
    Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "    $($_.Name) | Min: $($_.MinPasswordLength) chars | Prec: $($_.Precedence)"
    }

    Write-Host ""
    Write-Host "  Ultimo reporte de auditoria:" -ForegroundColor White
    if (Test-Path $REPORTE_PATH) {
        $info = Get-Item $REPORTE_PATH
        Write-Host "    $REPORTE_PATH"
        Write-Host "    Modificado: $($info.LastWriteTime)"
        Write-Host "    Tamano: $($info.Length) bytes"
    }
    else {
        Write-Warn "    No se ha generado reporte aun"
    }
    Write-Host ""
}
