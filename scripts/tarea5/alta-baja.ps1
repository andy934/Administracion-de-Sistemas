# ============================================================
#   alta-baja.ps1
#   Funciones de gestion de usuarios FTP
#   Se importa desde ftp-config.ps1 con . .\alta-baja.ps1
# ============================================================

# ============================================================
# Alta de un usuario FTP
# ============================================================
function Alta-Usuario {
    Write-Host ""
    Write-Host "=== ALTA DE USUARIO FTP ===" -ForegroundColor Cyan
    Write-Host ""

    # Validar nombre
    do {
        $usuario = Read-Host "Nombre de usuario"
        if ($usuario -notmatch "^[a-z][a-z0-9_-]{2,15}$") {
            Write-Host "[ERROR] Nombre invalido. Use 3-16 caracteres: minusculas, numeros, guion." `
                -ForegroundColor Red
            $usuario = $null
        }
    } while (-not $usuario)

    if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
        Write-Host "[ERROR] El usuario '$usuario' ya existe." -ForegroundColor Red
        return
    }

    # Contrasena
    do {
        $pass1 = Read-Host "Contrasena" -AsSecureString
        $pass2 = Read-Host "Confirmar contrasena" -AsSecureString
        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
        if ($p1 -ne $p2) {
            Write-Host "[ERROR] Las contrasenas no coinciden." -ForegroundColor Red
            $pass1 = $null
        } elseif ($p1.Length -lt 6) {
            Write-Host "[ERROR] Minimo 6 caracteres." -ForegroundColor Red
            $pass1 = $null
        }
    } while (-not $pass1)

    # Grupo
    Write-Host ""
    Write-Host "Seleccione el grupo:"
    Write-Host "  1. reprobados"
    Write-Host "  2. recursadores"
    $op = Read-Host "Opcion (1 o 2)"
    switch ($op) {
        "1" { $grupo = "reprobados" }
        "2" { $grupo = "recursadores" }
        default { Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red; return }
    }

    Write-Host ""
    Write-Host "[INFO] Creando usuario '$usuario' en grupo '$grupo'..."

    # Crear usuario local
    New-LocalUser -Name $usuario -Password $pass1 -FullName $usuario `
        -Description "Usuario FTP $grupo" -PasswordNeverExpires $true -ErrorAction Stop

    # Agregar al grupo
    Add-LocalGroupMember -Group $grupo -Member $usuario

    # Crear estructura de directorios con junctions
    # LocalUser\$usuario = raiz del chroot (equivalente a /srv/ftp/$USER en Linux)
    $userRoot = "$FTP_ROOT\LocalUser\$usuario"

    $dirs = @("$FTP_ROOT\LocalUser", $userRoot, "$userRoot\$usuario")
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Raiz del chroot: solo lectura para el usuario
    Establecer-Permisos-NTFS $userRoot $usuario "ReadAndExecute"

    # Carpeta personal: escritura solo para el usuario
    Establecer-Permisos-NTFS "$userRoot\$usuario" $usuario "Modify"

    # Junction a /general (equivalente a bind mount de Linux)
    $jGeneral = "$userRoot\general"
    if (Test-Path $jGeneral) { cmd /c "rmdir `"$jGeneral`"" | Out-Null }
    cmd /c "mklink /J `"$jGeneral`" `"$FTP_ROOT\general`"" | Out-Null

    # Junction a la carpeta de grupo
    $jGrupo = "$userRoot\$grupo"
    if (Test-Path $jGrupo) { cmd /c "rmdir `"$jGrupo`"" | Out-Null }
    cmd /c "mklink /J `"$jGrupo`" `"$FTP_ROOT\$grupo`"" | Out-Null

    # Permiso de escritura en la carpeta de grupo real
    Establecer-Permisos-NTFS "$FTP_ROOT\$grupo" $usuario "Modify"

    # Reiniciar sitio para aplicar cambios
    if (Importar-WebAdmin) {
        Stop-WebSite  -Name $SITE_NAME -ErrorAction SilentlyContinue
        Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "[OK] Usuario '$usuario' creado exitosamente" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "  Grupo     : $grupo"
    Write-Host "  Directorio: $userRoot"
    Write-Host ""
    Write-Host "  Estructura visible al conectar por FTP:"
    Write-Host "    /          (raiz — solo lectura)"
    Write-Host "    /general   (lectura/escritura — todos)"
    Write-Host "    /$grupo    (lectura/escritura — grupo $grupo)"
    Write-Host "    /$usuario  (lectura/escritura — solo $usuario)"
    Write-Host "==========================================" -ForegroundColor Green
}

# ============================================================
# Alta masiva de usuarios
# ============================================================
function Alta-Masiva-Usuarios {
    Write-Host ""
    Write-Host "=== ALTA MASIVA DE USUARIOS FTP ===" -ForegroundColor Cyan
    Write-Host ""

    $cantidad = Read-Host "Cuantos usuarios desea crear"
    if ($cantidad -notmatch "^\d+$" -or [int]$cantidad -lt 1) {
        Write-Host "[ERROR] Cantidad invalida." -ForegroundColor Red
        return
    }

    for ($i = 1; $i -le [int]$cantidad; $i++) {
        Write-Host ""
        Write-Host "----------------------------------------"
        Write-Host "Usuario $i de $cantidad"
        Write-Host "----------------------------------------"
        Alta-Usuario
    }

    Write-Host ""
    Write-Host "[OK] Alta masiva completada." -ForegroundColor Green
    Listar-Usuarios
}

# ============================================================
# Baja de un usuario FTP
# ============================================================
function Baja-Usuario {
    Write-Host ""
    Write-Host "=== BAJA DE USUARIO FTP ===" -ForegroundColor Cyan
    Write-Host ""

    $usuario = Read-Host "Nombre de usuario a eliminar"

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] El usuario '$usuario' no existe." -ForegroundColor Red
        return
    }

    $confirmar = Read-Host "ADVERTENCIA: Se eliminara '$usuario' y sus archivos. Seguro? (s/n)"
    if ($confirmar -ne "s" -and $confirmar -ne "S") {
        Write-Host "[INFO] Operacion cancelada."
        return
    }

    Write-Host "[INFO] Eliminando usuario '$usuario'..."

    # Eliminar usuario del sistema
    Remove-LocalUser -Name $usuario -ErrorAction SilentlyContinue

    # Eliminar junctions antes de borrar la carpeta (para no borrar directorios reales)
    $userRoot = "$FTP_ROOT\LocalUser\$usuario"
    if (Test-Path $userRoot) {
        Get-ChildItem $userRoot | Where-Object {
            $_.Attributes -band [IO.FileAttributes]::ReparsePoint
        } | ForEach-Object {
            cmd /c "rmdir `"$($_.FullName)`"" | Out-Null
        }
        Remove-Item $userRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Importar-WebAdmin) {
        Stop-WebSite  -Name $SITE_NAME -ErrorAction SilentlyContinue
        Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    }

    Write-Host "[OK] Usuario '$usuario' eliminado correctamente." -ForegroundColor Green
}

# ============================================================
# Cambiar grupo de un usuario
# ============================================================
function Cambiar-Grupo-Usuario {
    Write-Host ""
    Write-Host "=== CAMBIO DE GRUPO DE USUARIO ===" -ForegroundColor Cyan
    Write-Host ""

    $usuario = Read-Host "Nombre de usuario"

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] El usuario '$usuario' no existe." -ForegroundColor Red
        return
    }

    # Detectar grupo actual
    $grupoActual = $null
    foreach ($g in $GRUPOS) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -like "*\$usuario" }) {
            $grupoActual = $g; break
        }
    }

    Write-Host "  Grupo actual: $(if ($grupoActual) { $grupoActual } else { 'ninguno' })"
    Write-Host ""
    Write-Host "Seleccione el nuevo grupo:"
    Write-Host "  1. reprobados"
    Write-Host "  2. recursadores"
    $op = Read-Host "Opcion (1 o 2)"

    switch ($op) {
        "1" { $nuevoGrupo = "reprobados" }
        "2" { $nuevoGrupo = "recursadores" }
        default { Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red; return }
    }

    if ($grupoActual -eq $nuevoGrupo) {
        Write-Host "[INFO] El usuario ya pertenece al grupo '$nuevoGrupo'."
        return
    }

    Write-Host "[INFO] Cambiando de '$grupoActual' a '$nuevoGrupo'..."

    # Quitar del grupo anterior y agregar al nuevo
    if ($grupoActual) {
        Remove-LocalGroupMember -Group $grupoActual -Member $usuario -ErrorAction SilentlyContinue
    }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario

    $userRoot = "$FTP_ROOT\LocalUser\$usuario"

    # Reemplazar junction del grupo anterior
    if ($grupoActual -and (Test-Path "$userRoot\$grupoActual")) {
        cmd /c "rmdir `"$userRoot\$grupoActual`"" | Out-Null
    }
    $jNuevo = "$userRoot\$nuevoGrupo"
    if (Test-Path $jNuevo) { cmd /c "rmdir `"$jNuevo`"" | Out-Null }
    cmd /c "mklink /J `"$jNuevo`" `"$FTP_ROOT\$nuevoGrupo`"" | Out-Null

    # Revocar acceso al grupo anterior y otorgar al nuevo
    if ($grupoActual) {
        try {
            $acl = Get-Acl "$FTP_ROOT\$grupoActual"
            $acl.Access | Where-Object { $_.IdentityReference -like "*$usuario*" } |
                ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
            Set-Acl "$FTP_ROOT\$grupoActual" $acl
        } catch {}
    }
    Establecer-Permisos-NTFS "$FTP_ROOT\$nuevoGrupo" $usuario "Modify"

    if (Importar-WebAdmin) {
        Stop-WebSite  -Name $SITE_NAME -ErrorAction SilentlyContinue
        Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    }

    Write-Host "[OK] Usuario '$usuario' ahora pertenece al grupo '$nuevoGrupo'." -ForegroundColor Green
    Write-Host "     La carpeta /$nuevoGrupo ya esta disponible en su sesion FTP."
}

# ============================================================
# Listar usuarios FTP registrados
# ============================================================
function Listar-Usuarios {
    Write-Host ""
    Write-Host "=== USUARIOS FTP REGISTRADOS ===" -ForegroundColor Cyan
    Write-Host ""

    $linea = "+" + "-"*18 + "+" + "-"*14 + "+" + "-"*38 + "+"
    Write-Host $linea
    Write-Host ("| {0,-16} | {1,-12} | {2,-36} |" -f "Usuario", "Grupo", "Directorio Chroot")
    Write-Host $linea

    $total = 0
    foreach ($grupo in $GRUPOS) {
        $miembros = Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue
        foreach ($m in $miembros) {
            $nombre = $m.Name -replace ".*\\", ""
            $dir    = "$FTP_ROOT\LocalUser\$nombre"
            Write-Host ("| {0,-16} | {1,-12} | {2,-36} |" -f $nombre, $grupo, $dir)
            $total++
        }
    }

    Write-Host $linea
    Write-Host ""
    Write-Host "Total de usuarios FTP: $total"
    Write-Host ""
    foreach ($grupo in $GRUPOS) {
        $miembros = (Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue) |
                    ForEach-Object { $_.Name -replace ".*\\", "" }
        Write-Host "  ${grupo}: $($miembros -join ', ')"
    }
}

# ============================================================
# Ver permisos de un usuario especifico
# ============================================================
function Ver-Permisos-Usuario {
    Write-Host ""
    Write-Host "=== PERMISOS DE USUARIO FTP ===" -ForegroundColor Cyan
    Write-Host ""

    $usuario = Read-Host "Nombre de usuario"

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] El usuario '$usuario' no existe." -ForegroundColor Red
        return
    }

    $grupo = $null
    foreach ($g in $GRUPOS) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -like "*\$usuario" }) {
            $grupo = $g; break
        }
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "INFORMACION DEL USUARIO: $usuario"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Grupo : $(if ($grupo) { $grupo } else { 'Sin grupo FTP' })"
    Write-Host ""
    Write-Host "  ESTRUCTURA FTP (vista dentro del chroot):"
    Write-Host "  =========================================="

    $userRoot = "$FTP_ROOT\LocalUser\$usuario"
    $subdirs  = @(
        @{ Label = "/";          Ruta = $userRoot },
        @{ Label = "/general";   Ruta = "$userRoot\general" },
        @{ Label = "/$grupo";    Ruta = "$userRoot\$grupo" },
        @{ Label = "/$usuario";  Ruta = "$userRoot\$usuario" }
    )

    foreach ($s in $subdirs) {
        if (Test-Path $s.Ruta) {
            $attr = (Get-Item $s.Ruta -Force).Attributes
            $tipo = if ($attr -band [IO.FileAttributes]::ReparsePoint) { "[junction]" } else { "" }
            Write-Host ("  {0,-20}  Existe  {1}" -f $s.Label, $tipo)
        } else {
            Write-Host ("  {0,-20}  [NO EXISTE]" -f $s.Label) -ForegroundColor Yellow
        }
    }
    Write-Host "==========================================" -ForegroundColor Cyan
}
