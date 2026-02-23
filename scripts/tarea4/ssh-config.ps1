Write-Host "---------------------------------------------------"
Write-Host "-- Opcines.                                      --"
Write-Host "-- 1. Instalar SSH                          --"
Write-Host "-- 2. Status                                     --"
Write-Host "-- 3. Salir                                      --"
Write-Host "---------------------------------------------------"

$op = Read-Host "Elija una opcion: "

switch ($op) {
    1 {
        Write-Host "Instalando SSH..."
        #OpenSSH Client
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

        #OpenSSH Server
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        #Iniciar sshd service
        Start-Service sshd

        #Que inicie en automatico el servicio sshd
        Set-Service -Name sshd -StartupType 'Automatic'

        #Regla del firewall para permitir conexiones SSH 
        if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        }
    }
    2 {
        Write-Host "Verificando el estado del servicio SSH..."
        Get-Service -Name sshd
    }
    3 {
        Write-Host "Saliendo del programa."
        exit
    }
    default {
        Write-Host "Opción no válida. Por favor, elija una opción entre 1 y 3."
    }
}