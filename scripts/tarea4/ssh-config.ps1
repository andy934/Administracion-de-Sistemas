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
        # Install the OpenSSH Client
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

        # Install the OpenSSH Server
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        # Start the sshd service
        Start-Service sshd

        # OPTIONAL but recommended:
        Set-Service -Name sshd -StartupType 'Automatic'

        # Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
        if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
            Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        }
        else {
            Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
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