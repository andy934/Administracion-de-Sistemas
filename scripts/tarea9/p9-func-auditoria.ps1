# =============================================================================
# func-auditoria.ps1 - FGPP, Auditoria y Reporte de Eventos
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# =============================================================================

function Configurar-FGPP {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR DIRECTIVAS FGPP (PSOs)      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try { Get-ADDomain -ErrorAction Stop | Out-Null }
    catch { Write-Host "  [ERROR] No hay conexion a AD." -ForegroundColor Red; Read-Host | Out-Null; return }

    $fgppAdmin = "P09-FGPP-Admins"
    Write-Host "  [1/2] FGPP Administradores (12 chars, prioridad 10)..." -ForegroundColor Yellow
    try {
        $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'" -ErrorAction SilentlyContinue
        if ($existe) {
            Set-ADFineGrainedPasswordPolicy -Identity $fgppAdmin -MinPasswordLength 12 `
                -LockoutThreshold 3 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00"
            Write-Host "  [OK] '$fgppAdmin' actualizada." -ForegroundColor Yellow
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppAdmin `
                -DisplayName "FGPP Alta Seguridad - Administradores" `
                -Precedence 10 -ComplexityEnabled $true -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 5 -MinPasswordLength 12 `
                -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 3 -LockoutObservationWindow "00:30:00" -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] '$fgppAdmin': 12 chars, lockout 3/30min." -ForegroundColor Green
        }
        foreach ($s in @("Domain Admins","admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
            try { Add-ADFineGrainedPasswordPolicySubject -Identity $fgppAdmin -Subjects $s -ErrorAction Stop
                  Write-Host "    [+] Aplicada a: $s" -ForegroundColor DarkGreen } catch {}
        }
    } catch { Write-Host "  [ERROR] FGPP Admins: $($_.Exception.Message)" -ForegroundColor Red }

    $fgppStd = "P09-FGPP-Standard"
    Write-Host "`n  [2/2] FGPP Estandar (8 chars, prioridad 20)..." -ForegroundColor Yellow
    try {
        $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppStd'" -ErrorAction SilentlyContinue
        if ($existe) {
            Set-ADFineGrainedPasswordPolicy -Identity $fgppStd -MinPasswordLength 8
            Write-Host "  [OK] '$fgppStd' actualizada." -ForegroundColor Yellow
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppStd `
                -DisplayName "FGPP Estandar - Cuates y NoCuates" `
                -Precedence 20 -ComplexityEnabled $true -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 3 -MinPasswordLength 8 `
                -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 5 -LockoutObservationWindow "00:15:00" -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] '$fgppStd': 8 chars." -ForegroundColor Green
        }
        foreach ($s in @("Cuates","NoCuates")) {
            try { Add-ADFineGrainedPasswordPolicySubject -Identity $fgppStd -Subjects $s -ErrorAction Stop
                  Write-Host "    [+] Aplicada al grupo: $s" -ForegroundColor DarkGreen }
            catch { Write-Host "    [AVISO] No se pudo aplicar a '$s'." -ForegroundColor DarkGray }
        }
    } catch { Write-Host "  [ERROR] FGPP Standard: $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 5: Configurar auditoria y generar reporte ID 4625
# ------------------------------------------------------------

function Configurar-Auditoria {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   AUDITORIA DE EVENTOS Y REPORTE         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    Write-Host "  [1/3] Habilitando politicas de auditoria..." -ForegroundColor Yellow
    foreach ($p in @("Logon","Account Lockout","File System","Other Object Access Events","User Account Management")) {
        auditpol /set /subcategory:"$p" /success:enable /failure:enable 2>&1 | Out-Null
        Write-Host "  [OK] $p" -ForegroundColor Green
    }

    Write-Host "`n  [2/3] Aplicando GPO..." -ForegroundColor Yellow
    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO actualizada." -ForegroundColor Green

    Write-Host "`n  [3/3] Extrayendo eventos ID 4625..." -ForegroundColor Yellow
    $rutaReporte = "C:\MFA_Setup\Reporte_AccesosDenegados_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
    $enc = "==================================================" + [Environment]::NewLine +
           "REPORTE DE AUDITORIA DE SEGURIDAD"               + [Environment]::NewLine +
           "Practica 09 - Hardening Active Directory"         + [Environment]::NewLine +
           "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" + [Environment]::NewLine +
           "Servidor : $env:COMPUTERNAME"                    + [Environment]::NewLine +
           "Dominio  : $env:USERDNSDOMAIN"                   + [Environment]::NewLine +
           "Evento   : ID 4625 - Inicio de sesion fallido"   + [Environment]::NewLine +
           "==================================================" + [Environment]::NewLine
    try {
        $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue
        $enc | Out-File $rutaReporte -Encoding UTF8
        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [AVISO] Sin eventos ID 4625 aun." -ForegroundColor Yellow
            "No se encontraron eventos de acceso denegado (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
        } else {
            Write-Host "  [OK] $($eventos.Count) evento(s). Exportando..." -ForegroundColor Green
            $i = 1
            foreach ($e in $eventos) {
                $xml  = [xml]$e.ToXml()
                $user = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName"   }).'#text'
                $dom  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
                $ip   = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "IpAddress"        }).'#text'
                ("EVENTO $i de $($eventos.Count)"                               + [Environment]::NewLine +
                 "--------------------------------------------------"           + [Environment]::NewLine +
                 "Fecha    : $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))" + [Environment]::NewLine +
                 "Usuario  : $user"                                              + [Environment]::NewLine +
                 "Dominio  : $dom"                                               + [Environment]::NewLine +
                 "IP origen: $ip"                                                + [Environment]::NewLine +
                 "--------------------------------------------------"           + [Environment]::NewLine
                ) | Out-File $rutaReporte -Append -Encoding UTF8
                $i++
            }
        }
        Write-Host "  [OK] Reporte: $rutaReporte" -ForegroundColor Green
        Write-Host "`n  --- CONTENIDO ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" }
        Write-Host "  -----------------" -ForegroundColor Cyan
    } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 6: Instalar VC++ 2022 y multiOTP
# ------------------------------------------------------------

