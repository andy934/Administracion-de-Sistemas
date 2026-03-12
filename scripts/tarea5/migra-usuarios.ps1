# migrar-usuarios.ps1
# Migra usuarios de ftproot\LocalUser\$usuario a ftproot\$usuario
# que es la ruta correcta para StartInUsersDirectory en este servidor

$FTP_ROOT = "C:\inetpub\ftproot"
$GRUPOS   = @("reprobados", "recursadores")

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " MIGRACION DE USUARIOS FTP"                -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$usuarios = Get-ChildItem "$FTP_ROOT\LocalUser" -Directory |
            Where-Object { $_.Name -ne "Public" }

if ($usuarios.Count -eq 0) {
    Write-Host "[INFO] No hay usuarios en LocalUser para migrar."
    exit 0
}

foreach ($u in $usuarios) {
    $nombre  = $u.Name
    $origen  = $u.FullName
    $destino = "$FTP_ROOT\$nombre"

    Write-Host "--- Migrando: $nombre ---"

    # Crear carpeta raiz del usuario en ftproot\$usuario
    if (-not (Test-Path $destino)) {
        New-Item -ItemType Directory $destino -Force | Out-Null
        Write-Host "  [OK] Creado: $destino"
    } else {
        Write-Host "  [INFO] Ya existe: $destino"
    }

    # Detectar grupo del usuario
    $grupoUsuario = $null
    foreach ($g in $GRUPOS) {
        $miembros = net localgroup $g 2>&1
        foreach ($linea in $miembros) {
            if ($linea.Trim() -eq $nombre) {
                $grupoUsuario = $g
                break
            }
        }
        if ($grupoUsuario) { break }
    }
    Write-Host "  Grupo: $(if ($grupoUsuario) { $grupoUsuario } else { 'ninguno' })"

    # Eliminar junctions incorrectas y recrear correctas
    # Primero limpiar todo lo que hay en destino
    Get-ChildItem $destino -Force | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$($_.FullName)`"" | Out-Null
        }
    }

    # Crear carpeta personal del usuario
    $carpetaPersonal = "$destino\$nombre"
    if (-not (Test-Path $carpetaPersonal)) {
        New-Item -ItemType Directory $carpetaPersonal -Force | Out-Null
        Write-Host "  [OK] Carpeta personal: $carpetaPersonal"
    }

    # Junction a general
    $jGeneral = "$destino\general"
    if (Test-Path $jGeneral) { cmd /c "rmdir `"$jGeneral`"" | Out-Null }
    cmd /c "mklink /J `"$jGeneral`" `"$FTP_ROOT\general`"" | Out-Null
    Write-Host "  [OK] Junction: $jGeneral"

    # Junction al grupo
    if ($grupoUsuario) {
        $jGrupo = "$destino\$grupoUsuario"
        if (Test-Path $jGrupo) { cmd /c "rmdir `"$jGrupo`"" | Out-Null }
        cmd /c "mklink /J `"$jGrupo`" `"$FTP_ROOT\$grupoUsuario`"" | Out-Null
        Write-Host "  [OK] Junction: $jGrupo"
    }

    # Permisos NTFS
    $cuenta = "$env:COMPUTERNAME\$nombre"
    # Raiz: solo lectura para el usuario (chroot)
    icacls $destino /grant "${cuenta}:(OI)(CI)(RX)" 2>&1 | Out-Null
    icacls $destino /grant "Todos:(OI)(CI)(RX)" 2>&1 | Out-Null
    # Carpeta personal: escritura
    icacls $carpetaPersonal /grant "${cuenta}:(OI)(CI)(F)" 2>&1 | Out-Null
    # Carpeta de grupo: escritura
    if ($grupoUsuario) {
        icacls "$FTP_ROOT\$grupoUsuario" /grant "${cuenta}:(OI)(CI)(F)" 2>&1 | Out-Null
    }
    Write-Host "  [OK] Permisos configurados"
    Write-Host ""
}

# Reiniciar servicio
Restart-Service FTPSVC -Force
Write-Host "Estado FTPSVC: $((Get-Service FTPSVC).Status)" -ForegroundColor Green

# Mostrar resultado
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " ESTRUCTURA FINAL"                          -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
foreach ($u in $usuarios) {
    $destino = "$FTP_ROOT\$($u.Name)"
    Write-Host "  $($u.Name):"
    Get-ChildItem $destino -Force | ForEach-Object {
        $tipo = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { "[junction]" } else { "[dir]" }
        Write-Host "    /$($_.Name)  $tipo"
    }
}
Write-Host ""
Write-Host "Prueba conectarte con: ftp $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike '*Loopback*' } | Select-Object -First 1).IPAddress)"