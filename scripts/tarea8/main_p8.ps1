# ================================================================
#  main_p8.ps1  |  Menu principal  |  Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.10.11
# ================================================================

. "$PSScriptRoot\funciones_p8.ps1"

# -- Verificar privilegios de Administrador ----------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  --------------------------------------------------------" -ForegroundColor Red
    Write-Host "  ERROR  Este script requiere privilegios de Administrador." -ForegroundColor Red
    Write-Host "         Abre PowerShell como Admin e intenta de nuevo."     -ForegroundColor Red
    Write-Host "  --------------------------------------------------------" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# -- Bucle principal ---------------------------------------------
do {
    Clear-Host
    Write-Host "  ================================================================" -ForegroundColor White
    Write-Host "                 A C T I V E    D I R E C T O R Y                 " -ForegroundColor Blue
    Write-Host "  ================================================================" -ForegroundColor White
    Write-Host ""
    Write-Host "     [1]   Instalar dependencias"                                     -ForegroundColor White
    Write-Host "     [2]   Promover servidor a Domain Controller"                     -ForegroundColor White
    Write-Host "     [3]   Crear OUs y usuarios desde CSV"                            -ForegroundColor White
    Write-Host "     [4]   Configurar horarios de acceso"                             -ForegroundColor White
    Write-Host "     [5]   Configurar cuotas FSRM"                                    -ForegroundColor White
    Write-Host "     [6]   Configurar apantallamiento FSRM"                           -ForegroundColor White
    Write-Host "     [7]   Configurar AppLocker"                                      -ForegroundColor White
    Write-Host "     [8]   Crear usuario dinamicamente"                               -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor White
    Write-Host "     [0]   Salir"                                                     -ForegroundColor Red
    Write-Host ""

    $opcion = Read-Host "  Opcion"

    switch ($opcion) {
        "1" { Instalar-Dependencias      }
        "2" { Promover-DomainController  }
        "3" { Crear-OUsYUsuarios         }
        "4" { Configurar-Horarios        }
        "5" { Configurar-CuotasFSRM      }
        "6" { Configurar-Apantallamiento }
        "7" { Configurar-AppLocker       }
        "8" { Crear-UsuarioDinamico      }
        "0" {
            Write-Host ""
            Write-Host "  Saliendo" -ForegroundColor Gray
            Write-Host ""
            break # Sale del switch
        }
        default {
            Write-Host ""
            Write-Host "  Opcion invalida. Elige un numero del 0 al 8." -ForegroundColor White
            Write-Host ""
        }
    }

    # -- Pausa después de ejecutar cualquier opción (excepto salir) --
    if ($opcion -ne "0" -and $opcion -ne "") {
        Write-Host ""
        Write-Host "  Presiona ENTER para volver al menu..." -ForegroundColor White
        Read-Host
    }

} while ($opcion -ne "0")