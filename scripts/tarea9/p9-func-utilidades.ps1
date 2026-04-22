# =============================================================================
# func-utilidades.ps1 - Funciones de utilidad compartidas
# Practica 9 - Seguridad de Identidad, Delegacion y MFA
# =============================================================================

# ============================================================
#  funciones_p9.ps1 -- Libreria de funciones Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA TOTP
#  Version final - todos los tests automatizados
# ============================================================

# ------------------------------------------------------------
# UTILIDAD: Detectar nombre real de OUs creadas en P08
# ------------------------------------------------------------
function Get-OUSegura {
    param([string]$NombreBase)
    $dcBase    = (Get-ADDomain).DistinguishedName
    $variantes = @($NombreBase, ($NombreBase -replace ' ',''))
    foreach ($v in $variantes) {
        try {
            Get-ADOrganizationalUnit -Identity "OU=$v,$dcBase" -ErrorAction Stop | Out-Null
            return "OU=$v,$dcBase"
        } catch {}
    }
    Write-Host "  [AVISO] OU '$NombreBase' no existe. Creandola..." -ForegroundColor Yellow
    try {
        New-ADOrganizationalUnit -Name $NombreBase -Path $dcBase -ErrorAction Stop
        Write-Host "  [OK] OU '$NombreBase' creada." -ForegroundColor Green
        return "OU=$NombreBase,$dcBase"
    } catch {
        Write-Host "  [ERROR] No se pudo crear OU '$NombreBase': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ------------------------------------------------------------
# UTILIDAD: Localizar multiotp.exe
# ------------------------------------------------------------
function Get-MultiOTPExe {
    foreach ($r in @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")) {
        if (Test-Path "$r\multiotp.exe") { return "$r\multiotp.exe" }
    }
    return $null
}

# ------------------------------------------------------------
# UTILIDAD: Permitir login local en el DC a un usuario
# ------------------------------------------------------------
function Habilitar-LogonLocal {
    param([string]$Usuario)
    try {
        $sid     = (Get-ADUser $Usuario -ErrorAction Stop).SID.Value
        $cfgPath = "C:\MFA_Setup\secpol_temp.cfg"
        secedit /export /cfg $cfgPath /quiet 2>&1 | Out-Null
        $contenido = Get-Content $cfgPath -Raw
        if ($contenido -match "SeInteractiveLogonRight.*\*$sid") {
            Write-Host "    [OK] ${Usuario}: ya tiene logon local." -ForegroundColor DarkGray
            return
        }
        $contenido = $contenido -replace "(SeInteractiveLogonRight\s*=\s*)(.*)",       "`$1`$2,*$sid"
        $contenido = $contenido -replace "(SeRemoteInteractiveLogonRight\s*=\s*)(.*)", "`$1`$2,*$sid"
        $contenido | Set-Content $cfgPath -Encoding Unicode
        secedit /configure /cfg $cfgPath /db "C:\MFA_Setup\secedit.sdb" /quiet 2>&1 | Out-Null
        Write-Host "    [OK] ${Usuario}: logon local y RDP habilitados." -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] No se pudo habilitar logon para ${Usuario}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
