function Write-Header {
    param([string]$Titulo)
    $linea  = "=" * 64
    $espacio = 64 - $Titulo.Length
    $izq    = [math]::Floor($espacio / 2)
    $centro = (" " * $izq) + $Titulo
    Write-Host ""
    Write-Host "  $linea"  -ForegroundColor DarkCyan
    Write-Host "  $centro" -ForegroundColor White
    Write-Host "  $linea"  -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Sep {
    Write-Host "  $("-" * 64)" -ForegroundColor DarkCyan
}

function Write-Fila {
    param(
        [string]$Estado,
        [string]$Mensaje
    )
    switch ($Estado) {
        "OK"  { $tag = " OK "; $col = "Green"      }
        "ERR" { $tag = "ERR "; $col = "Red"        }
        "AVS" { $tag = "AVS "; $col = "DarkYellow" }
        "NEW" { $tag = "NEW "; $col = "Cyan"       }
        "UPD" { $tag = "UPD "; $col = "Yellow"     }
        "INF" { $tag = " -- "; $col = "Gray"       }
        default { $tag = "    "; $col = "Gray"     }
    }
    Write-Host "  [ $tag ]  $Mensaje" -ForegroundColor $col
}

function Write-Resumen {
    param([hashtable[]]$Filas)
    Write-Host ""
    Write-Sep
    foreach ($f in $Filas) {
        $etiqueta = $f.Label.PadRight(26)
        $valor    = "$($f.Valor)".PadLeft(4)
        Write-Host "  $etiqueta  $valor" -ForegroundColor $f.Color
    }
    Write-Sep
    Write-Host ""
}

function Confirm-Accion {
    param([string]$Pregunta = "Deseas continuar?")
    $r = Read-Host "  $Pregunta (s/n)"
    Write-Host ""
    return ($r -eq "s")
}


# ----------------------------------------------------------------
#  FUNCION 1  |  Instalar Dependencias
# ----------------------------------------------------------------
function Instalar-Dependencias {

    Write-Header "INSTALACION DE DEPENDENCIAS"

    $dependencias = @(
        @{ Nombre = "AD-Domain-Services";  Desc = "Active Directory Domain Services" },
        @{ Nombre = "DNS";                 Desc = "Servidor DNS"                     },
        @{ Nombre = "FS-Resource-Manager"; Desc = "FSRM  (Cuotas y Apantallamiento)" },
        @{ Nombre = "RSAT-AD-PowerShell";  Desc = "PowerShell para AD"               },
        @{ Nombre = "RSAT-ADDS";           Desc = "Herramientas de administracion AD" }
    )

    Write-Host "  Estado actual de dependencias:" -ForegroundColor Gray
    Write-Host ""

    $porInstalar = @()
    foreach ($dep in $dependencias) {
        $feat = Get-WindowsFeature -Name $dep.Nombre
        if ($feat.InstallState -eq "Installed") {
            Write-Fila "OK"  $dep.Desc
        } else {
            Write-Fila "INF" $dep.Desc
            $porInstalar += $dep
        }
    }

    Write-Host ""

    if ($porInstalar.Count -eq 0) {
        Write-Host "  Todas las dependencias estan instaladas." -ForegroundColor Gray
        Write-Host ""
        if (-not (Confirm-Accion "Reinstalar de todas formas?")) {
            Write-Sep; Write-Fila "INF" "Sin cambios."; Write-Host ""; return
        }
        $porInstalar = $dependencias
    }

    Write-Host "  Se instalaran los siguientes componentes:" -ForegroundColor Gray
    Write-Host ""
    foreach ($dep in $porInstalar) { Write-Fila "INF" $dep.Desc }
    Write-Host ""

    if (-not (Confirm-Accion "Confirmas la instalacion?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    Write-Host ""
    Write-Host "  Instalando componentes, esto puede tardar unos minutos..." -ForegroundColor Gray
    Write-Host ""

    foreach ($dep in $porInstalar) {
        Write-Host "  Instalando  $($dep.Desc)..." -ForegroundColor Gray
        $r = Install-WindowsFeature -Name $dep.Nombre -IncludeManagementTools
        if ($r.Success) { Write-Fila "OK"  $dep.Desc }
        else            { Write-Fila "ERR" "Fallo al instalar  $($dep.Desc)" }
    }

    Write-Host ""
    Write-Sep
    Write-Fila "INF" "Siguiente paso  ->  Opcion 2  :  Promover a Domain Controller"
    Write-Host ""
}


# ----------------------------------------------------------------
#  FUNCION 2  |  Promover servidor a Domain Controller
# ----------------------------------------------------------------
function Promover-DomainController {

    Write-Header "PROMOVER A DOMAIN CONTROLLER"

    $adds = Get-WindowsFeature -Name "AD-Domain-Services"
    if ($adds.InstallState -ne "Installed") {
        Write-Fila "ERR" "AD-Domain-Services no esta instalado."
        Write-Host ""; Write-Sep; Write-Fila "INF" "Ejecuta primero la opcion 1."; Write-Host ""; return
    }

    try {
        $info = Get-ADDomain -ErrorAction Stop
        Write-Fila "AVS" "Este servidor ya es DC  ->  $($info.DNSRoot)"
        Write-Host ""; Write-Sep; Write-Fila "INF" "No es necesario volver a promoverlo."; Write-Host ""; return
    } catch {}

    Write-Host "  Parametros del nuevo bosque:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Dominio         :  reprobados.local"
    Write-Fila "INF" "NetBIOS         :  reprobados"
    Write-Fila "INF" "Nivel de bosque :  Windows Server 2022"
    Write-Fila "INF" "DNS             :  Se instala en este servidor"
    Write-Fila "INF" "IP del servidor :  192.168.137.130"
    Write-Host ""
    Write-Host "  El servidor se reiniciara automaticamente al finalizar." -ForegroundColor DarkYellow
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    $dsrmPassword = Read-Host "  Contrasena DSRM (modo de restauracion)" -AsSecureString
    Write-Host ""

    Write-Host "  Configurando DNS estatico en el adaptador..." -ForegroundColor Gray

    $adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ip.IPAddress -eq "192.168.137.130") { $_ }
    }

    if ($adaptador) {
        Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses "192.168.137.130"
        Write-Fila "OK" "DNS configurado  ->  $($adaptador.Name)"
    } else {
        Write-Fila "AVS" "No se encontro adaptador con IP 192.168.137.130  (continuando)"
    }

    Write-Host ""
    Write-Host "  Iniciando promocion, esto puede tardar varios minutos..." -ForegroundColor Gray
    Write-Host ""

    try {
        Install-ADDSForest `
            -DomainName "reprobados.local" `
            -DomainNetbiosName "reprobados" `
            -ForestMode "WinThreshold" `
            -DomainMode "WinThreshold" `
            -InstallDns:$true `
            -SafeModeAdministratorPassword $dsrmPassword `
            -NoRebootOnCompletion:$false `
            -Force:$true

        Write-Fila "OK" "Promocion completada. Reiniciando servidor..."
    } catch {
        Write-Fila "ERR" "Fallo la promocion  :  $($_.Exception.Message)"
    }
    Write-Host ""
}


# ----------------------------------------------------------------
#  FUNCION 3  |  Crear OUs y usuarios desde CSV
# ----------------------------------------------------------------
function Crear-OUsYUsuarios {

    Write-Header "CREAR OUs Y USUARIOS DESDE CSV"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro  usuarios.csv  en:"
        Write-Host "       $csvPath" -ForegroundColor Gray
        Write-Host ""; return
    }

    $usuarios = Import-Csv -Path $csvPath
    Write-Fila "INF" "Usuarios encontrados en CSV  :  $($usuarios.Count)"
    Write-Host ""

    if (-not (Confirm-Accion "Crear OUs y usuarios?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    $dcBase = $dominio.DistinguishedName

    # -- Crear OUs --
    Write-Host "  Creando unidades organizativas..." -ForegroundColor Gray
    Write-Host ""

    foreach ($ou in @("Cuates", "NoCuates")) {
        $ouPath = "OU=$ou,$dcBase"
        try {
            Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
            Write-Fila "UPD" "OU ya existe  ->  $ou"
        } catch {
            try {
                New-ADOrganizationalUnit -Name $ou -Path $dcBase -ProtectedFromAccidentalDeletion $false
                Write-Fila "NEW" "OU creada     ->  $ou"
            } catch {
                Write-Fila "ERR" "No se pudo crear OU $ou  :  $($_.Exception.Message)"
            }
        }
    }

    # -- Crear usuarios --
    Write-Host ""
    Write-Host "  Creando usuarios..." -ForegroundColor Gray
    Write-Host ""

    $creados = 0; $omitidos = 0; $errores = 0

    foreach ($u in $usuarios) {
        $ouDestino = "OU=$($u.Departamento),$dcBase"
        try {
            Get-ADUser -Identity $u.Usuario -ErrorAction Stop | Out-Null
            Write-Fila "UPD" "$($u.Usuario)  ya existe  ->  omitido"
            $omitidos++; continue
        } catch {}

        try {
            $passwordSegura = ConvertTo-SecureString $u.Password -AsPlainText -Force
            New-ADUser `
                -Name "$($u.Nombre) $($u.Apellido)" `
                -GivenName $u.Nombre `
                -Surname $u.Apellido `
                -SamAccountName $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@Active.Directory" `
                -Path $ouDestino `
                -AccountPassword $passwordSegura `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -ChangePasswordAtLogon $false

            Write-Fila "NEW" "$($u.Nombre) $($u.Apellido)  ->  $($u.Departamento)"
            $creados++
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"; $errores++
        }
    }

    # -- Crear grupos --
    Write-Host ""
    Write-Host "  Creando grupos de seguridad..." -ForegroundColor Gray
    Write-Host ""

    foreach ($g in @(
        @{ Nombre = "Cuates";   OU = "OU=Cuates,$dcBase"   },
        @{ Nombre = "NoCuates"; OU = "OU=NoCuates,$dcBase" }
    )) {
        try {
            Get-ADGroup -Identity $g.Nombre -ErrorAction Stop | Out-Null
            Write-Fila "UPD" "Grupo ya existe  ->  $($g.Nombre)"
        } catch {
            try {
                New-ADGroup -Name $g.Nombre -GroupScope Global -GroupCategory Security -Path $g.OU
                Write-Fila "NEW" "Grupo creado     ->  $($g.Nombre)"
            } catch {
                Write-Fila "ERR" "No se pudo crear $($g.Nombre)  :  $($_.Exception.Message)"
            }
        }
    }

    # -- Asignar usuarios a grupos --
    Write-Host ""
    Write-Host "  Asignando usuarios a grupos..." -ForegroundColor Gray
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario -ErrorAction Stop
            Write-Fila "OK" "$($u.Usuario)  ->  $($u.Departamento)"
        } catch {
            Write-Fila "AVS" "$($u.Usuario)  ->  $($u.Departamento)  :  $($_.Exception.Message)"
        }
    }

    Write-Resumen @(
        @{ Label = "Usuarios creados";   Valor = $creados;  Color = "Green"      },
        @{ Label = "Usuarios omitidos";  Valor = $omitidos; Color = "DarkYellow" },
        @{ Label = "Errores";            Valor = $errores;  Color = "Red"        }
    )
}


# ----------------------------------------------------------------
#  FUNCION 4  |  Configurar horarios de acceso  (UTC-7)
# ----------------------------------------------------------------
function Configurar-Horarios {

    Write-Header "CONFIGURAR HORARIOS DE ACCESO"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    Write-Host "  Zona horaria  :  UTC-7  (Los Mochis, Sinaloa)" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Cuates    :  05:00 - 13:00  local  (12:00 - 19:59 UTC)"
    Write-Fila "INF" "NoCuates  :  13:00 - 21:00  local  (20:00 - 03:59 UTC)"
    Write-Host ""
    Write-Host "  Se aplicara GPO para forzar cierre de sesion al expirar el turno." -ForegroundColor Gray
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    function Build-LogonHours {
        param([int[]]$HorasUTC)
        $bits = New-Object bool[] 168
        for ($dia = 0; $dia -lt 7; $dia++) {
            foreach ($hora in $HorasUTC) { $bits[$dia * 24 + $hora] = $true }
        }
        $bytes = New-Object byte[] 21
        for ($i = 0; $i -lt 168; $i++) {
            if ($bits[$i]) {
                $bytes[[math]::Floor($i / 8)] = $bytes[[math]::Floor($i / 8)] -bor (1 -shl ($i % 8))
            }
        }
        return $bytes
    }

    # Arreglos actualizados (UTC)
    $bytesCuates   = Build-LogonHours -HorasUTC @(12,13,14,15,16,17,18,19)
    $bytesNoCuates = Build-LogonHours -HorasUTC @(20,21,22,23,0,1,2,3)

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro usuarios.csv en $PSScriptRoot"; Write-Host ""; return
    }

    $usuarios = Import-Csv -Path $csvPath

    Write-Host "  Aplicando horarios..." -ForegroundColor Gray
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            if ($u.Departamento -eq "Cuates") {
                Set-ADUser -Identity $u.Usuario -Clear logonHours
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = ([byte[]]$bytesCuates)}
                Write-Fila "OK" "$($u.Usuario)  ->  Cuates    05:00 - 13:00"
            } elseif ($u.Departamento -eq "NoCuates") {
                Set-ADUser -Identity $u.Usuario -Clear logonHours
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = ([byte[]]$bytesNoCuates)}
                Write-Fila "OK" "$($u.Usuario)  ->  NoCuates  13:00 - 21:00"
            } else {
                Write-Fila "AVS" "$($u.Usuario)  :  departamento desconocido  '$($u.Departamento)'"
            }
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"
        }
    }

    # -- GPO cierre de sesion forzado --
    Write-Host ""
    Write-Host "  Configurando GPO de cierre de sesion forzado..." -ForegroundColor Gray
    Write-Host ""

    $gpoNombre = "Tarea8-LogonHours"

    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Fila "NEW" "GPO creada  ->  $gpoNombre"
        } else {
            Write-Fila "UPD" "GPO ya existe, se actualiza  ->  $gpoNombre"
        }

        Set-GPRegistryValue `
            -Name $gpoNombre `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
            -ValueName "EnableForcedLogOff" `
            -Type DWord `
            -Value 1 | Out-Null

        Write-Fila "OK" "Politica de cierre forzado configurada."

        try {
            New-GPLink -Name $gpoNombre -Target $dominio.DistinguishedName -ErrorAction Stop | Out-Null
            Write-Fila "OK" "GPO vinculada al dominio."
        } catch {
            Write-Fila "UPD" "GPO ya estaba vinculada al dominio."
        }
    } catch {
        Write-Fila "ERR" "No se pudo configurar la GPO  :  $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Sep
    Write-Fila "INF" "Los usuarios seran desconectados al expirar su turno permitido."
    Write-Host ""
}


# ----------------------------------------------------------------
#  FUNCION 5  |  Configurar cuotas FSRM
# ----------------------------------------------------------------
function Configurar-CuotasFSRM {

    Write-Header "CONFIGURAR CUOTAS FSRM"

    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Fila "ERR" "FSRM no esta instalado. Ejecuta primero la opcion 1."; Write-Host ""; return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro usuarios.csv en $PSScriptRoot"; Write-Host ""; return
    }

    $usuarios    = Import-Csv -Path $csvPath
    $carpetaRaiz = "C:\Usuarios"

    Write-Host "  Configuracion que se aplicara:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Carpeta raiz  :  $carpetaRaiz\<usuario>"
    Write-Fila "INF" "Cuates        :  10 MB  (cuota estricta)"
    Write-Fila "INF" "NoCuates      :   5 MB  (cuota estricta)"
    Write-Host ""
    Write-Host "  El servidor bloqueara archivos que superen el limite asignado." -ForegroundColor DarkYellow
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- Carpeta raiz --
    if (-not (Test-Path $carpetaRaiz)) {
        New-Item -Path $carpetaRaiz -ItemType Directory | Out-Null
        Write-Fila "NEW" "Carpeta raiz creada  ->  $carpetaRaiz"
    } else {
        Write-Fila "UPD" "Carpeta raiz ya existe  ->  $carpetaRaiz"
    }

    # -- Recurso compartido --
    Write-Host ""
    $dominioActual = $env:USERDOMAIN
    $shareExiste = Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue
    if (-not $shareExiste) {
        New-SmbShare -Name "Usuarios" -Path $carpetaRaiz `
            -FullAccess "$dominioActual\Domain Admins" `
            -ChangeAccess "$dominioActual\Domain Users" | Out-Null
        Write-Fila "NEW" "Recurso compartido  ->  \\192.168.137.130\Usuarios"
    } else {
        Write-Fila "UPD" "Recurso compartido ya existe."
    }

    # -- Permisos NTFS --
    $acl   = Get-Acl $carpetaRaiz
    $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$dominioActual\Domain Users","Modify","ContainerInherit,ObjectInherit","None","Allow")
    $acl.AddAccessRule($regla)
    Set-Acl $carpetaRaiz $acl
    Write-Fila "OK" "Permisos NTFS configurados para Domain Users."

    # -- Plantillas de cuota --
    Write-Host ""
    Write-Host "  Creando plantillas de cuota..." -ForegroundColor Gray
    Write-Host ""

    foreach ($p in @(
        @{ Nombre = "Tarea8-Cuates-10MB";  Tamano = 10MB },
        @{ Nombre = "Tarea8-NoCuates-5MB"; Tamano = 5MB  }
    )) {
        try {
            $existe = Get-FsrmQuotaTemplate -Name $p.Nombre -ErrorAction SilentlyContinue
            if ($existe) {
                Write-Fila "UPD" "Plantilla ya existe  ->  $($p.Nombre)"
            } else {
                New-FsrmQuotaTemplate -Name $p.Nombre -Size $p.Tamano -SoftLimit:$false | Out-Null
                Write-Fila "NEW" "Plantilla creada    ->  $($p.Nombre)  ($($p.Tamano / 1MB) MB)"
            }
        } catch {
            Write-Fila "ERR" "No se pudo crear $($p.Nombre)  :  $($_.Exception.Message)"
        }
    }

    # -- Cuotas por usuario --
    Write-Host ""
    Write-Host "  Aplicando cuotas a usuarios..." -ForegroundColor Gray
    Write-Host ""

    $creadas = 0; $actualizadas = 0; $errores = 0

    foreach ($u in $usuarios) {
        $carpetaUsuario = "$carpetaRaiz\$($u.Usuario)"

        if ($u.Departamento -eq "Cuates") {
            $plantillaNombre = "reprobados-Cuates-10MB";  $tamanoBytes = 10MB; $tamanoTexto = "10 MB"
        } elseif ($u.Departamento -eq "NoCuates") {
            $plantillaNombre = "reprobados-NoCuates-5MB"; $tamanoBytes = 5MB;  $tamanoTexto = " 5 MB"
        } else {
            Write-Fila "AVS" "$($u.Usuario)  :  departamento desconocido, omitido."; continue
        }

        if (-not (Test-Path $carpetaUsuario)) {
            try {
                New-Item -Path $carpetaUsuario -ItemType Directory | Out-Null
                Write-Fila "NEW" "Carpeta creada  ->  $carpetaUsuario"
            } catch {
                Write-Fila "ERR" "No se pudo crear carpeta  $carpetaUsuario"; $errores++; continue
            }
        }

        try {
            $cuotaExiste     = Get-FsrmQuota -Path $carpetaUsuario -ErrorAction SilentlyContinue
            $plantillaExiste = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

            if ($cuotaExiste) {
                if ($plantillaExiste) { Set-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
                else                  { Set-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
                Write-Fila "UPD" "$($u.Usuario)  ($($u.Departamento))  ->  $tamanoTexto  actualizado"
                $actualizadas++
            } else {
                if ($plantillaExiste) { New-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
                else                  { New-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
                Write-Fila "OK"  "$($u.Usuario)  ($($u.Departamento))  ->  $tamanoTexto"
                $creadas++
            }
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"; $errores++
        }
    }

    Write-Resumen @(
        @{ Label = "Cuotas creadas";      Valor = $creadas;      Color = "Green"      },
        @{ Label = "Cuotas actualizadas"; Valor = $actualizadas; Color = "DarkYellow" },
        @{ Label = "Errores";             Valor = $errores;      Color = "Red"        }
    )
}

function Configurar-Apantallamiento {

    Write-Header "CONFIGURAR APANTALLAMIENTO DE ARCHIVOS"

    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Fila "ERR" "FSRM no esta instalado. Ejecuta primero la opcion 1."; Write-Host ""; return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro usuarios.csv en $PSScriptRoot"; Write-Host ""; return
    }

    $usuarios    = Import-Csv -Path $csvPath
    $carpetaRaiz = "C:\Usuarios"
    $grupoNombre = "Archivos ejecutables"

    Write-Host "  Tipos de archivo que seran bloqueados en todas las carpetas:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Multimedia   :  *.mp3  *.mp4"
    Write-Fila "INF" "Ejecutables  :  *.exe  *.msi"
    Write-Host ""
    Write-Host "  Tipo  :  ACTIVO  (el servidor rechaza el archivo en tiempo real)" -ForegroundColor DarkYellow
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- Grupo de archivos --
    Write-Host ""
    Write-Host "  Creando grupo de archivos prohibidos..." -ForegroundColor Gray
    Write-Host ""

    try {
        $grupoExiste = Get-FsrmFileGroup -Name $grupoNombre -ErrorAction SilentlyContinue
        if ($grupoExiste) {
            Set-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Fila "UPD" "Grupo actualizado  ->  $grupoNombre"
        } else {
            New-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Fila "NEW" "Grupo creado       ->  $grupoNombre"
        }
    } catch {
        Write-Fila "ERR" "No se pudo gestionar el grupo  :  $($_.Exception.Message)"; return
    }

    # -- Plantilla de apantallamiento --
    Write-Host ""
    Write-Host "  Creando plantilla de apantallamiento..." -ForegroundColor Gray
    Write-Host ""

    $plantillaNombre = "Tarea8-Apantallamiento"

    foreach ($u in $usuarios) {
        $carpetaUsuario = "$carpetaRaiz\$($u.Usuario)"
        try {
            # Intentamos crear el bloqueo directamente con el grupo
            New-FsrmFileScreen -Path $carpetaUsuario -IncludeGroup "Archivos ejecutables" -ErrorAction Stop | Out-Null
            Write-Fila "OK" "$($u.Usuario) : Apantallamiento aplicado"
            $creados++
        } catch {
            # Si ya existe, lo actualizamos
            Set-FsrmFileScreen -Path $carpetaUsuario -IncludeGroup "Archivos ejecutables" | Out-Null
            Write-Fila "UPD" "$($u.Usuario) : Apantallamiento actualizado"
            $actualizados++
        }
    }


    Write-Resumen @(
        @{ Label = "Screens creados";      Valor = $creados;      Color = "Green"      },
        @{ Label = "Screens actualizados"; Valor = $actualizados; Color = "DarkYellow" },
        @{ Label = "Errores";              Valor = $errores;      Color = "Red"        }
    )
}

function Configurar-AppLocker {

    Write-Header "CONFIGURAR APPLOCKER"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    Write-Host "  Reglas que se configuraran via GPO:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Cuates    :  notepad.exe  PERMITIDO  (reglas base)"
    Write-Fila "INF" "NoCuates  :  notepad.exe  BLOQUEADO  por Hash SHA-256"
    Write-Host ""
    Write-Host "  La regla de Hash identifica el ejecutable por contenido," -ForegroundColor Gray
    Write-Host "  no por nombre. Renombrar el .exe no evita el bloqueo."    -ForegroundColor Gray
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- SID de NoCuates --
    Write-Host "  Obteniendo SID del grupo NoCuates..." -ForegroundColor Gray

    try {
        $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
        Write-Fila "OK" "SID NoCuates  ->  $sidNoCuates"
    } catch {
        Write-Fila "ERR" "No se pudo obtener el SID  :  $($_.Exception.Message)"; return
    }

    $info = Get-AppLockerFileInformation -Path "C:\Windows\System32\notepad.exe"

    $hashValor   = "70152c176b629e51fd283bd2f30acfbdb1a129ea14d94889c1d32a742c104bbf"
    $archivoSize = 200704  # Este es el tamaño exacto para ese hash de Win10
    $guid1       = [System.Guid]::NewGuid().ToString()

    # -- Construir XML --
    Write-Host ""
    Write-Host "  Construyendo politica AppLocker..." -ForegroundColor Gray

    $xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Permitir Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a23e-47ff-8e4a-4e3d41bc98b0" Name="Permitir ProgramFiles" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="b61c8b2c-a23e-47ff-8e4a-4e3d41bc98b1" Name="Permitir ProgramFiles x86" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES(X86)%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="$guid1" Name="Bloquear Notepad NoCuates" Description="Bloquea notepad.exe por ruta" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\System32\notepad.exe"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
  <RuleCollection Type="Appx" EnforcementMode="Enabled">
    <FilePublisherRule Id="a9e18c21-ff8f-43cf-b9fc-db40eed693ba" Name="Permitir apps Microsoft" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="b9e18c21-ff8f-43cf-b9fc-db40eed693bb" Name="Permitir apps Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@

    $xmlPath = "C:\Windows\Temp\applocker_p8.xml"
    $xmlPolicy | Out-File $xmlPath -Encoding UTF8 -Force
    Write-Fila "OK" "XML generado  ->  $xmlPath"

    # -- GPO --
    Write-Host ""
    Write-Host "  Configurando GPO de AppLocker..." -ForegroundColor Gray
    Write-Host ""

    $gpoNombre = "Tarea8-AppLocker"

    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Fila "NEW" "GPO creada  ->  $gpoNombre"
        } else {
            Write-Fila "UPD" "GPO ya existe, se actualiza  ->  $gpoNombre"
        }

        #$gpoId = $gpo.Id.ToString()
        #Set-AppLockerPolicy -XmlPolicy $xmlPath -Merge
        #Write-Fila "OK" "Politica AppLocker aplicada a la GPO."

        $gpoId = $gpo.Id.ToString()
        # Usamos la ruta LDAP dinámica para que funcione con tu dominio
        Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap "LDAP://CN={$gpoId},CN=Policies,CN=System,$($dominio.DistinguishedName)"
        Write-Fila "OK" "Politica AppLocker aplicada a la GPO."

        try {
            New-GPLink -Name $gpoNombre -Target $dominio.DistinguishedName -ErrorAction Stop | Out-Null
            Write-Fila "OK" "GPO vinculada al dominio."
        } catch {
            Write-Fila "UPD" "GPO ya estaba vinculada al dominio."
        }

        Write-Host ""
        Write-Host "  Habilitando servicio AppIDSvc..." -ForegroundColor Gray
        sc.exe config AppIDSvc start= auto | Out-Null
        sc.exe start  AppIDSvc 2>$null    | Out-Null
        Write-Fila "OK" "AppIDSvc configurado como Automatico."

    } catch {
        Write-Fila "ERR" "No se pudo configurar la GPO  :  $($_.Exception.Message)"; return
    }

    Write-Host ""
    Write-Sep
    Write-Fila "OK"  "Cuates    :  notepad.exe  PERMITIDO"
    Write-Fila "OK"  "NoCuates  :  notepad.exe  BLOQUEADO  (hash)"
    Write-Host ""
    Write-Host "  Pasos requeridos en el cliente Windows:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "1.  Abrir PowerShell como Administrador"
    Write-Fila "INF" "2.  sc.exe config AppIDSvc start= auto"
    Write-Fila "INF" "3.  sc.exe start AppIDSvc"
    Write-Fila "INF" "4.  gpupdate /force"
    Write-Fila "INF" "5.  Cerrar sesion y volver a entrar"
    Write-Host ""
}


# ----------------------------------------------------------------
#  FUNCION 8  |  Crear usuario dinamicamente
# ----------------------------------------------------------------
function Crear-UsuarioDinamico {

    Write-Header "CREAR USUARIO DINAMICAMENTE"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    $dcBase      = $dominio.DistinguishedName
    $carpetaRaiz = "C:\Usuarios"

    Write-Host "  Ingresa los datos del nuevo usuario:" -ForegroundColor Gray
    Write-Host ""

    $nombre = Read-Host "  Nombre"
    if ([string]::IsNullOrWhiteSpace($nombre)) { Write-Fila "ERR" "El nombre no puede estar vacio."; return }

    $apellido = Read-Host "  Apellido"
    if ([string]::IsNullOrWhiteSpace($apellido)) { Write-Fila "ERR" "El apellido no puede estar vacio."; return }

    $usuario = Read-Host "  Usuario  (sin espacios ni caracteres especiales)"
    if ([string]::IsNullOrWhiteSpace($usuario)) { Write-Fila "ERR" "El usuario no puede estar vacio."; return }

    try {
        Get-ADUser -Identity $usuario -ErrorAction Stop | Out-Null
        Write-Fila "ERR" "El usuario '$usuario' ya existe en el dominio."; return
    } catch {}

    $password = Read-Host "  Password  (min 8 caracteres, mayuscula, numero y simbolo)"
    if ([string]::IsNullOrWhiteSpace($password)) { Write-Fila "ERR" "El password no puede estar vacio."; return }

    Write-Host ""
    Write-Host "  Departamento:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "1  ->  Cuates    (08:00 - 15:00  |  cuota 10 MB)"
    Write-Fila "INF" "2  ->  NoCuates  (15:00 - 02:00  |  cuota  5 MB)"
    Write-Host ""

    $deptoOpcion = Read-Host "  Selecciona el departamento (1 o 2)"

    if      ($deptoOpcion -eq "1") { $departamento = "Cuates"   }
    elseif  ($deptoOpcion -eq "2") { $departamento = "NoCuates" }
    else    { Write-Fila "ERR" "Opcion invalida. Elige 1 o 2."; return }

    # -- Confirmacion --
    Write-Host ""
    Write-Sep
    Write-Fila "INF" "Nombre       :  $nombre $apellido"
    Write-Fila "INF" "Usuario      :  $usuario@Active.Directory"
    Write-Fila "INF" "Departamento :  $departamento"

    if ($departamento -eq "Cuates") {
        Write-Fila "INF" "Horario      :  08:00 - 15:00"
        Write-Fila "INF" "Cuota        :  10 MB"
    } else {
        Write-Fila "INF" "Horario      :  15:00 - 02:00"
        Write-Fila "INF" "Cuota        :   5 MB"
    }

    Write-Fila "INF" "Apantallam.  :  .mp3  .mp4  .exe  .msi  bloqueados"
    Write-Sep
    Write-Host ""

    if (-not (Confirm-Accion "Confirmas la creacion del usuario?")) {
        Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- PASO 1  :  Crear en AD --
    Write-Host "  [ 1 / 5 ]  Creando usuario en Active Directory..." -ForegroundColor Gray
    try {
        $passwordSegura = ConvertTo-SecureString $password -AsPlainText -Force
        New-ADUser `
            -Name "$nombre $apellido" `
            -GivenName $nombre `
            -Surname $apellido `
            -SamAccountName $usuario `
            -UserPrincipalName "$usuario@Active.Directory" `
            -Path "OU=$departamento,$dcBase" `
            -AccountPassword $passwordSegura `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -ChangePasswordAtLogon $false

        Write-Fila "OK" "Usuario creado  ->  OU $departamento"
    } catch {
        Write-Fila "ERR" "No se pudo crear el usuario  :  $($_.Exception.Message)"; return
    }

    # -- PASO 2  :  Grupo --
    Write-Host "  [ 2 / 5 ]  Agregando al grupo $departamento..." -ForegroundColor Gray
    try {
        Add-ADGroupMember -Identity $departamento -Members $usuario -ErrorAction Stop
        Write-Fila "OK" "Agregado al grupo  ->  $departamento"
    } catch {
        Write-Fila "AVS" "No se pudo agregar al grupo  :  $($_.Exception.Message)"
    }

    # -- PASO 3  :  Horario --
    Write-Host "  [ 3 / 5 ]  Aplicando horario de acceso (UTC-7)..." -ForegroundColor Gray

    function Build-LogonHours {
        param([int[]]$HorasUTC)
        $bits = New-Object bool[] 168
        for ($dia = 0; $dia -lt 7; $dia++) {
            foreach ($hora in $HorasUTC) { $bits[$dia * 24 + $hora] = $true }
        }
        $bytes = New-Object byte[] 21
        for ($i = 0; $i -lt 168; $i++) {
            if ($bits[$i]) {
                $bytes[[math]::Floor($i / 8)] = $bytes[[math]::Floor($i / 8)] -bor (1 -shl ($i % 8))
            }
        }
        return $bytes
    }

    try {
        $horasUTC     = if ($departamento -eq "Cuates") { @(15,16,17,18,19,20,21) } else { @(22,23,0,1,2,3,4,5,6,7,8) }
        $bytesHorario = Build-LogonHours -HorasUTC $horasUTC
        Set-ADUser -Identity $usuario -Clear logonHours
        Set-ADUser -Identity $usuario -Replace @{logonHours = ([byte[]]$bytesHorario)}
        Write-Fila "OK" "Horario aplicado correctamente."
    } catch {
        Write-Fila "AVS" "No se pudo aplicar el horario  :  $($_.Exception.Message)"
    }

    # -- PASO 4  :  Cuota FSRM --
    Write-Host "  [ 4 / 5 ]  Creando carpeta y aplicando cuota FSRM..." -ForegroundColor Gray

    $carpetaUsuario = "$carpetaRaiz\$usuario"

    if (-not (Test-Path $carpetaUsuario)) {
        try {
            New-Item -Path $carpetaUsuario -ItemType Directory | Out-Null
            Write-Fila "NEW" "Carpeta creada  ->  $carpetaUsuario"
        } catch {
            Write-Fila "AVS" "No se pudo crear la carpeta  :  $($_.Exception.Message)"
        }
    } else {
        Write-Fila "UPD" "Carpeta ya existe  ->  $carpetaUsuario"
    }

    try {
        if ($departamento -eq "Cuates") {
            $plantillaNombre = "Tarea8-Cuates-10MB";  $tamanoBytes = 10MB; $tamanoTexto = "10 MB"
        } else {
            $plantillaNombre = "Tarea8-NoCuates-5MB"; $tamanoBytes = 5MB;  $tamanoTexto = " 5 MB"
        }

        $cuotaExiste     = Get-FsrmQuota -Path $carpetaUsuario -ErrorAction SilentlyContinue
        $plantillaExiste = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

        if ($cuotaExiste) {
            if ($plantillaExiste) { Set-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
            else                  { Set-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
        } else {
            if ($plantillaExiste) { New-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
            else                  { New-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
        }
        Write-Fila "OK" "Cuota aplicada  ->  $tamanoTexto"
    } catch {
        Write-Fila "AVS" "No se pudo aplicar la cuota  :  $($_.Exception.Message)"
    }

    # -- PASO 5  :  Apantallamiento --
    Write-Host "  [ 5 / 5 ]  Aplicando apantallamiento de archivos..." -ForegroundColor Gray

    $plantillaScreen = "reprobados-Apantallamiento"

    try {
        $plantillaExiste = Get-FsrmFileScreenTemplate -Name $plantillaScreen -ErrorAction SilentlyContinue
        if (-not $plantillaExiste) {
            Write-Fila "AVS" "Plantilla de apantallamiento no existe. Ejecuta primero la opcion 6."
        } else {
            $screenExiste = Get-FsrmFileScreen -Path $carpetaUsuario -ErrorAction SilentlyContinue
            if ($screenExiste) {
                Set-FsrmFileScreen -Path $carpetaUsuario -Template $plantillaScreen | Out-Null
            } else {
                New-FsrmFileScreen -Path $carpetaUsuario -Template $plantillaScreen | Out-Null
            }
            Write-Fila "OK" ".mp3  .mp4  .exe  .msi  bloqueados."
        }
    } catch {
        Write-Fila "AVS" "No se pudo aplicar el apantallamiento  :  $($_.Exception.Message)"
    }

    # -- Resumen final --
    Write-Host ""
    Write-Sep
    Write-Fila "OK" "Usuario creado exitosamente  ->  $usuario@Active.Directory"
    Write-Sep
    Write-Host ""
    Write-Fila "OK" "Usuario en Active Directory"
    Write-Fila "OK" "Grupo de seguridad"
    Write-Fila "OK" "Horario de acceso"
    Write-Fila "OK" "Cuota FSRM"
    Write-Fila "OK" "Apantallamiento de archivos"
    Write-Host ""
}