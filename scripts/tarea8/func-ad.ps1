# =============================================================================
# func-ad.ps1 - Active Directory: instalacion, dominio, OUs y usuarios
# Practica 8 - Administracion de Sistemas
# Sistema: Windows Server 2022
# =============================================================================

$DOMAIN        = "reprobados.com"
$DOMAIN_NETBIOS = "REPROBADOS"
$DOMAIN_DN     = "DC=reprobados,DC=com"
$SAFE_PASS     = "Sistemas.2026"   # Contrasena de recuperacion DSRM
$OU_CUATES     = "OU=Cuates,$DOMAIN_DN"
$OU_NO_CUATES  = "OU=NoCuates,$DOMAIN_DN"
$CSV_PATH      = "$PSScriptRoot\usuarios.csv"

# =============================================================================
# VALIDACIONES
# =============================================================================

function AD-Instalado {
    return (Get-WindowsFeature AD-Domain-Services -ErrorAction SilentlyContinue).Installed
}

function AD-Configurado {
    try {
        Get-ADDomain -ErrorAction SilentlyContinue | Out-Null
        return $true
    } catch { return $false }
}

function Validar-AD {
    if (AD-Configurado) { return $true }
    Write-Warn "Active Directory no esta configurado"
    $r = Read-Host "  Instalar y configurar AD ahora? [S/n]"
    if ($r -match '^[nN]$') { return $false }
    Instalar-AD-Completo
    return (AD-Configurado)
}

# =============================================================================
# PASO 1: INSTALAR ROL AD DS
# =============================================================================

function Instalar-Rol-ADDS {
    Write-Info "Instalando rol Active Directory Domain Services..."

    if ((Get-WindowsFeature AD-Domain-Services).Installed) {
        Write-Info "Rol AD DS ya instalado"
        return $true
    }

    $result = Install-WindowsFeature -Name AD-Domain-Services `
        -IncludeManagementTools -IncludeAllSubFeature

    if ($result.Success) {
        Write-OK "Rol AD DS instalado correctamente"
        return $true
    } else {
        Write-Err "Fallo la instalacion del rol AD DS"
        return $false
    }
}

# =============================================================================
# PASO 2: PROMOVER A CONTROLADOR DE DOMINIO
# =============================================================================

function Promover-Controlador-Dominio {
    Write-Info "Promoviendo servidor a Controlador de Dominio..."
    Write-Info "  Dominio : $DOMAIN"
    Write-Info "  NetBIOS : $DOMAIN_NETBIOS"
    Write-Warn "El servidor se reiniciara automaticamente al finalizar"
    Write-Host ""

    $safePass = ConvertTo-SecureString $SAFE_PASS -AsPlainText -Force

    try {
        Install-ADDSForest `
            -DomainName $DOMAIN `
            -DomainNetbiosName $DOMAIN_NETBIOS `
            -SafeModeAdministratorPassword $safePass `
            -InstallDns:$true `
            -Force:$true `
            -NoRebootOnCompletion:$false

        Write-OK "Controlador de dominio configurado. El servidor se reiniciara."
    } catch {
        Write-Err "Error al promover controlador de dominio: $_"
        return $false
    }
    return $true
}

# =============================================================================
# INSTALACION COMPLETA (rol + promocion)
# =============================================================================

function Instalar-AD-Completo {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   INSTALACION DE ACTIVE DIRECTORY        " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Configurar IP estatica si es necesario
    Configurar-IP-Estatica

    if (-not (Instalar-Rol-ADDS)) { return }

    Write-Host ""
    Write-Warn "Tras la instalacion del rol, el servidor necesita"
    Write-Warn "ser promovido a DC. Esto requiere reinicio."
    $r = Read-Host "  Promover a DC ahora? [S/n]"
    if ($r -notmatch '^[nN]$') {
        Promover-Controlador-Dominio
    }
}

# =============================================================================
# CONFIGURAR IP ESTATICA
# =============================================================================

function Configurar-IP-Estatica {
    Write-Info "Verificando configuracion de red..."

    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $adapter) { Write-Warn "No se encontro adaptador de red activo"; return }

    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex `
        -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $ipConfig) { Write-Warn "No se pudo obtener IP actual"; return }

    $currentIP  = $ipConfig.IPAddress
    $prefix     = $ipConfig.PrefixLength
    $gateway    = (Get-NetRoute -InterfaceIndex $adapter.ifIndex `
        -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Select-Object -First 1).NextHop

    Write-Info "  Adaptador: $($adapter.Name)"
    Write-Info "  IP actual: $currentIP/$prefix"
    Write-Info "  Gateway  : $gateway"

    $r = Read-Host "  Configurar IP estatica? [S/n]"
    if ($r -match '^[nN]$') { return }

    $newIP = Read-Host "  Nueva IP [$currentIP]"
    if (-not $newIP) { $newIP = $currentIP }

    # Remover configuracion DHCP y asignar estatica
    $adapter | Set-NetIPInterface -Dhcp Disabled -ErrorAction SilentlyContinue
    $adapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    $adapter | New-NetIPAddress -IPAddress $newIP -PrefixLength $prefix `
        -DefaultGateway $gateway -ErrorAction SilentlyContinue | Out-Null

    # DNS apuntando a si mismo
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
        -ServerAddresses @("127.0.0.1", "8.8.8.8")

    Write-OK "IP estatica configurada: $newIP"
    Write-OK "DNS primario: 127.0.0.1 (se mismo)"
}

# =============================================================================
# CREAR UNIDADES ORGANIZATIVAS
# =============================================================================

function Crear-OUs {
    if (-not (Validar-AD)) { return }
    Write-Info "Creando Unidades Organizativas..."

    $ous = @(
        @{ Name = "Cuates";   Path = $DOMAIN_DN; Desc = "Grupo con acceso 8AM-3PM" },
        @{ Name = "NoCuates"; Path = $DOMAIN_DN; Desc = "Grupo con acceso 3PM-2AM" }
    )

    foreach ($ou in $ous) {
        $ouDN = "OU=$($ou.Name),$($ou.Path)"
        if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue) {
            Write-Info "OU '$($ou.Name)' ya existe"
        } else {
            New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path `
                -Description $ou.Desc -ProtectedFromAccidentalDeletion $false
            Write-OK "OU '$($ou.Name)' creada en $($ou.Path)"
        }
    }
}

# =============================================================================
# CREAR GRUPOS DE SEGURIDAD
# =============================================================================

function Crear-Grupos {
    if (-not (Validar-AD)) { return }
    Write-Info "Creando grupos de seguridad..."

    $grupos = @(
        @{ Name = "GrupoCuates";   OU = $OU_CUATES;    Desc = "Grupo Cuates - acceso 8AM-3PM" },
        @{ Name = "GrupoNoCuates"; OU = $OU_NO_CUATES; Desc = "Grupo No Cuates - acceso 3PM-2AM" }
    )

    foreach ($g in $grupos) {
        if (Get-ADGroup -Filter "Name -eq '$($g.Name)'" -ErrorAction SilentlyContinue) {
            Write-Info "Grupo '$($g.Name)' ya existe"
        } else {
            New-ADGroup -Name $g.Name -GroupScope Global `
                -GroupCategory Security -Path $g.OU `
                -Description $g.Desc
            Write-OK "Grupo '$($g.Name)' creado"
        }
    }
}

# =============================================================================
# CREAR USUARIOS DESDE CSV
# =============================================================================

function Crear-Usuarios-CSV {
    param([string]$CsvPath = $CSV_PATH)

    if (-not (Validar-AD)) { return }

    if (-not (Test-Path $CsvPath)) {
        Write-Err "Archivo CSV no encontrado: $CsvPath"
        Write-Err "Asegurate de que usuarios.csv este en la misma carpeta que los scripts"
        return
    }

    Write-Info "Leyendo usuarios desde: $CsvPath"
    $usuarios = Import-Csv $CsvPath
    Write-Info "Total usuarios en CSV: $($usuarios.Count)"
    Write-Host ""

    $creados = 0; $errores = 0; $existentes = 0

    foreach ($u in $usuarios) {
        # Determinar OU segun Departamento
        $ouPath = switch ($u.Departamento) {
            "Cuates"   { $OU_CUATES }
            "NoCuates" { $OU_NO_CUATES }
            default    { $OU_NO_CUATES }
        }

        $grupo = switch ($u.Departamento) {
            "Cuates"   { "GrupoCuates" }
            "NoCuates" { "GrupoNoCuates" }
            default    { "GrupoNoCuates" }
        }

        # Verificar si ya existe
        if (Get-ADUser -Filter "SamAccountName -eq '$($u.Usuario)'" -ErrorAction SilentlyContinue) {
            Write-Info "Usuario '$($u.Usuario)' ya existe - omitiendo"
            $existentes++
            continue
        }

        try {
            $pass = ConvertTo-SecureString $u.Contrasena -AsPlainText -Force

            New-ADUser `
                -Name            "$($u.Nombre) $($u.Apellido)" `
                -GivenName       $u.Nombre `
                -Surname         $u.Apellido `
                -SamAccountName  $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@$DOMAIN" `
                -Path            $ouPath `
                -AccountPassword $pass `
                -Enabled         $true `
                -PasswordNeverExpires $false `
                -ChangePasswordAtLogon $false `
                -Department      $u.Departamento `
                -Description     "Usuario $($u.Departamento) - Practica 8"

            # Agregar al grupo correspondiente
            Add-ADGroupMember -Identity $grupo -Members $u.Usuario -ErrorAction SilentlyContinue

            # Crear carpeta personal
            Crear-Carpeta-Usuario -Usuario $u.Usuario -Departamento $u.Departamento

            Write-OK "[$($u.Departamento)] $($u.Usuario) - $($u.Nombre) $($u.Apellido)"
            $creados++
        } catch {
            Write-Err "Error creando $($u.Usuario): $_"
            $errores++
        }
    }

    Write-Host ""
    Write-OK "Resumen: $creados creados | $existentes existentes | $errores errores"
}

# =============================================================================
# CREAR CARPETA PERSONAL DEL USUARIO
# =============================================================================

function Crear-Carpeta-Usuario {
    param([string]$Usuario, [string]$Departamento)

    $baseDir = "C:\Usuarios"
    $userDir = "$baseDir\$Usuario"

    if (-not (Test-Path $baseDir)) {
        New-Item -ItemType Directory -Path $baseDir | Out-Null
        # Compartir la carpeta base
        if (-not (Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue)) {
            New-SmbShare -Name "Usuarios" -Path $baseDir `
                -FullAccess "Administradores" `
                -ChangeAccess "Usuarios autenticados" | Out-Null
        }
    }

    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Path $userDir | Out-Null

        # Asignar permisos: solo el usuario y admins
        $acl = Get-Acl $userDir
        $acl.SetAccessRuleProtection($true, $false)

        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administradores", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$DOMAIN_NETBIOS\$Usuario", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")

        $acl.AddAccessRule($adminRule)
        $acl.AddAccessRule($userRule)
        Set-Acl $userDir $acl -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# MOSTRAR RESUMEN DE USUARIOS Y OUs
# =============================================================================

function Mostrar-Estado-AD {
    if (-not (AD-Configurado)) {
        Write-Warn "Active Directory no configurado"
        return
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   ESTADO DE ACTIVE DIRECTORY             " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $domain = Get-ADDomain
    Write-Host "  Dominio : $($domain.DNSRoot)" -ForegroundColor White
    Write-Host "  DC      : $($domain.PDCEmulator)" -ForegroundColor White
    Write-Host "  DN      : $($domain.DistinguishedName)" -ForegroundColor White
    Write-Host ""

    foreach ($ouName in @("Cuates", "NoCuates")) {
        $ouDN = "OU=$ouName,$DOMAIN_DN"
        $usuarios = Get-ADUser -Filter * -SearchBase $ouDN `
            -Properties Department -ErrorAction SilentlyContinue
        Write-Host "  OU $ouName`: $($usuarios.Count) usuarios" -ForegroundColor Cyan
        $usuarios | ForEach-Object {
            Write-Host "    - $($_.SamAccountName) ($($_.Name))"
        }
        Write-Host ""
    }
}
