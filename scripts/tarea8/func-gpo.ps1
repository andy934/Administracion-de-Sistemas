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
    Write-Host ""
    Write-Info "Configurando AppLocker (Reglas de Hash para Notepad)..."

    $notepadPath = "C:\Windows\System32\notepad.exe"
    $xmlPath     = "$env:TEMP\applocker-p8.xml"

    if (-not (Test-Path $notepadPath)) {
        Write-Err "notepad.exe no encontrado en $notepadPath"
        return
    }

    # Obtener hash de notepad.exe
    $hashInfo = Get-AppLockerFileInformation -Path $notepadPath
    if (-not $hashInfo -or -not $hashInfo.Hash) {
        Write-Err "No se pudo obtener informacion de hash de notepad.exe"
        return
    }

    # --- CORRECCIÓN ESPECÍFICA ---
    # Eliminamos cualquier "0x" que ya traiga el hash para que no se duplique
    $hashData = $hashInfo.Hash.HashDataString -replace "0x", ""
    # -----------------------------

    $fileSize = (Get-Item $notepadPath).Length

    # Obtener SID del grupo NoCuates
    $sidNoCuates = (Get-ADGroup "GrupoNoCuates" -ErrorAction SilentlyContinue).SID.Value
    if (-not $sidNoCuates) {
        Write-Err "No se encontro el grupo GrupoNoCuates"
        return
    }

    Write-Info "   Hash SHA256 notepad.exe: $hashData"
    Write-Info "   SID GrupoNoCuates: $sidNoCuates"

    # Generar XML de politica AppLocker directamente
    # Ahora $hashData no tiene 0x, por lo que "0x$hashData" sera correcto
    $xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20"
      Name="(Default) Todos en Windows"
      Description="Permite ejecutar apps en Windows a todos"
      UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a23e-4fb7-a6bb-2b4da6c0f4a1"
      Name="(Default) Todos en Program Files"
      Description="Permite ejecutar apps en Program Files a todos"
      UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
      Name="(Default) Administradores todo"
      Description="Permite a administradores ejecutar todo"
      UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
    <FileHashRule Id="b9c3a6f2-1234-5678-abcd-ef0123456789"
      Name="Bloquear Notepad para NoCuates por Hash"
      Description="P8 - NoCuates no pueden usar Notepad aunque lo renombren"
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$hashData"
            SourceFileName="notepad.exe" SourceFileLength="$fileSize"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
</AppLockerPolicy>
"@

    try {
        $xml | Set-Content -Path $xmlPath -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy $xmlPath -Merge
        Write-OK "Politica AppLocker aplicada correctamente"
        Write-OK "  GrupoNoCuates: Notepad BLOQUEADO por hash SHA256"
        Write-OK "  GrupoCuates  : Notepad PERMITIDO (reglas por defecto)"
    } catch {
        Write-Warn "Error aplicando AppLocker: $($_.Exception.Message)"
        Write-Info "XML guardado en: $xmlPath"
    }

    Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    Write-OK "Servicio AppIDSvc habilitado"
    Remove-Item $xmlPath -ErrorAction SilentlyContinue
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