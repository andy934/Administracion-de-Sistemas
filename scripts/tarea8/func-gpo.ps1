# =============================================================================
# func-gpo.ps1 - GPO: Logon Hours y AppLocker
# Practica 8 - Administracion de Sistemas
# Sistema: Windows Server 2022
# =============================================================================

# =============================================================================
# LOGON HOURS
# Representacion: array de 21 bytes (3 bytes por dia, 7 dias)
# Cada bit = 1 hora. Bit 0 = 12AM, Bit 1 = 1AM, ...
# =============================================================================

function Calcular-LogonHours {
    param(
        [int]$HoraInicio,   # 0-23
        [int]$HoraFin       # 0-23 (exclusivo)
    )

    # Crear array de 168 bits (24 horas x 7 dias)
    $bits = New-Object bool[] 168

    for ($dia = 0; $dia -lt 7; $dia++) {
        if ($HoraFin -gt $HoraInicio) {
            # Rango simple: ej 8 a 15
            for ($h = $HoraInicio; $h -lt $HoraFin; $h++) {
                $bits[$dia * 24 + $h] = $true
            }
        } else {
            # Rango que cruza medianoche: ej 15 a 2 (3PM a 2AM)
            for ($h = $HoraInicio; $h -lt 24; $h++) {
                $bits[$dia * 24 + $h] = $true
            }
            for ($h = 0; $h -lt $HoraFin; $h++) {
                $bits[$dia * 24 + $h] = $true
            }
        }
    }

    # Convertir bits a bytes (21 bytes) - usar [int] para evitar division flotante
    $bytes = New-Object byte[] 21
    for ($i = 0; $i -lt 168; $i++) {
        if ($bits[$i]) {
            $byteIdx = [int]([math]::Floor($i / 8))
            $bitIdx  = $i % 8
            $bytes[$byteIdx] = [byte]($bytes[$byteIdx] -bor (1 -shl $bitIdx))
        }
    }
    return $bytes
}

function Aplicar-LogonHours-Grupo {
    param(
        [string]$Grupo,
        [int]$HoraInicio,
        [int]$HoraFin,
        [string]$Descripcion
    )

    Write-Info "Configurando horario para grupo '$Grupo': $Descripcion"

    $bytes = Calcular-LogonHours -HoraInicio $HoraInicio -HoraFin $HoraFin

    $usuarios = Get-ADGroupMember -Identity $Grupo -ErrorAction SilentlyContinue |
                Where-Object { $_.objectClass -eq 'user' }

    if (-not $usuarios) {
        Write-Warn "No se encontraron usuarios en el grupo $Grupo"
        return
    }

    $count = 0
    foreach ($u in $usuarios) {
        Set-ADUser -Identity $u.SamAccountName -Replace @{logonHours = [byte[]]$bytes}
        $count++
    }
    Write-OK "Horario aplicado a $count usuarios del grupo $Grupo"
}

function Configurar-LogonHours {
    if (-not (Validar-AD)) { return }
    Write-Info "Configurando horarios de inicio de sesion..."
    Write-Host ""

    # Cuates: 8AM a 3PM (8 a 15)
    Aplicar-LogonHours-Grupo `
        -Grupo "GrupoCuates" `
        -HoraInicio 8 `
        -HoraFin 15 `
        -Descripcion "8:00 AM - 3:00 PM"

    # No Cuates: 3PM a 2AM (15 a 2)
    Aplicar-LogonHours-Grupo `
        -Grupo "GrupoNoCuates" `
        -HoraInicio 15 `
        -HoraFin 2 `
        -Descripcion "3:00 PM - 2:00 AM"

    Write-Host ""
    Write-OK "Horarios configurados correctamente"
}

# =============================================================================
# GPO: FORZAR CIERRE DE SESION AL EXPIRAR HORARIO
# =============================================================================

function Configurar-GPO-LogonHours {
    if (-not (Validar-AD)) { return }
    Write-Info "Configurando GPO para cerrar sesion al expirar horario..."

    $gpoName = "P8-LogonHours-ForceLogoff"

    # Crear GPO si no existe
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoName -Comment "Practica 8 - Cierre de sesion por horario"
        Write-OK "GPO '$gpoName' creada"
    } else {
        Write-Info "GPO '$gpoName' ya existe"
    }

    # Configurar: Network security - Force logoff when logon hours expire
    # Clave de registro: HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters\EnableForcedLogOff
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
        -ValueName "EnableForcedLogOff" `
        -Type DWord -Value 1

    # Tambien via Security Options
    $gpoPath = "\\$env:USERDNSDOMAIN\SYSVOL\$env:USERDNSDOMAIN\Policies\{$($gpo.Id)}"

    # Vincular GPO al dominio
    $link = Get-GPInheritance -Target $DOMAIN_DN -ErrorAction SilentlyContinue
    $linked = $link.GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
    if (-not $linked) {
        New-GPLink -Name $gpoName -Target $DOMAIN_DN -LinkEnabled Yes
        Write-OK "GPO vinculada al dominio $DOMAIN_DN"
    } else {
        Write-Info "GPO ya vinculada"
    }

    Write-OK "GPO de cierre de sesion configurada"
}

# =============================================================================
# APPLOCKER: NOTEPAD
# Cuates: pueden usar Notepad
# No Cuates: bloqueado por hash (no se puede evadir renombrando)
# =============================================================================

function Configurar-AppLocker {
    Write-Info "Configurando AppLocker..."

    $notepadPath = "C:\Windows\System32\notepad.exe"
    $xmlPath = "$env:TEMP\applocker-p8.xml"

    # 1. Obtener la información del archivo correctamente
    # Esto genera un objeto que ya contiene el Hash válido
    $fileInfo = Get-AppLockerFileInformation -Path $notepadPath -FileType Exe

    # 2. Crear las reglas basadas en los grupos de la práctica
    # Importante: Usar el nombre exacto de tus grupos (GrupoCuates y GrupoNoCuates)
    $ruleCuates = New-AppLockerPolicy -FileInformation $fileInfo -Action Allow -User "REPROBADOS\GrupoCuates"
    $ruleNoCuates = New-AppLockerPolicy -FileInformation $fileInfo -Action Deny -User "REPROBADOS\GrupoNoCuates"

    # 3. Crear reglas predeterminadas (INDISPENSABLE)
    # Sin estas reglas, NADIE (incluyendo el Administrador) podrá ejecutar nada en Windows
    $defaultRules = New-AppLockerPolicy -ReferenceLog -User "Everyone" -RuleType Path, Hash, Publisher

    # 4. Generar la política final combinando todo
    # Esto evita el error del 0x0x porque PowerShell genera el XML automáticamente
    try {
        $fullPolicy = New-AppLockerPolicy -FileInformation $fileInfo -RuleType Hash -User "Everyone"
        $fullPolicy | Export-Xml -Path $xmlPath # O usar Set-AppLockerPolicy directamente
        
        # Aplicar la política
        Set-AppLockerPolicy -XmlPolicy $xmlPath -Merge
        Write-OK "AppLocker configurado: Cuates (Allow) / No Cuates (Deny) para Notepad."
    } catch {
        Write-Warn "Error aplicando AppLocker: $($_.Exception.Message)"
    }

    # Asegurar que el servicio de Identidad de Aplicación esté corriendo
    Set-Service -Name AppIDSvc -StartupType Automatic
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
}
# =============================================================================
# RESUMEN DE GPOs
# =============================================================================

function Mostrar-Estado-GPO {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DE GPOs Y POLITICAS             " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $gpos = Get-GPO -All -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "P8-*" }

    if ($gpos) {
        Write-Host "  GPOs de Practica 8:" -ForegroundColor White
        $gpos | ForEach-Object {
            $st = if ($_.GpoStatus -eq 'AllSettingsEnabled') { "[ON]" } else { "[--]" }
            Write-Host "    $st $($_.DisplayName)"
        }
    } else {
        Write-Warn "  No se encontraron GPOs de Practica 8"
    }

    Write-Host ""
    Write-Host "  Horarios configurados:" -ForegroundColor White
    foreach ($grupo in @("GrupoCuates", "GrupoNoCuates")) {
        $miembros = Get-ADGroupMember $grupo -ErrorAction SilentlyContinue |
                    Where-Object { $_.objectClass -eq 'user' }
        $horario = if ($grupo -eq "GrupoCuates") { "8AM-3PM" } else { "3PM-2AM" }
        Write-Host "    $grupo`: $($miembros.Count) usuarios | Horario: $horario"
    }
    Write-Host ""
}