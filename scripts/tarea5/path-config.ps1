# patch-config.ps1
# Inserta las reglas de autorizacion FTP en applicationHost.config

$ahConfig = "$env:windir\system32\inetsrv\config\applicationHost.config"
Copy-Item $ahConfig "$ahConfig.bak4" -Force

$contenido = [System.IO.File]::ReadAllText($ahConfig, [System.Text.Encoding]::UTF8)

$ssl    = 'controlChannelPolicy="SslAllow" dataChannelPolicy="SslAllow" />'
$cierre = '</security>'

$buscar = $ssl + "`r`n                    " + $cierre

$insertar  = '<authorization>' + "`r`n"
$insertar += '                            <add accessType="Allow" users="" roles="" permissions="Read" />' + "`r`n"
$insertar += '                            <add accessType="Allow" users="*" roles="" permissions="Read, Write" />' + "`r`n"
$insertar += '                        </authorization>'

$reemplazar = $ssl + "`r`n                        " + $insertar + "`r`n                    " + $cierre

$nuevo = $contenido.Replace($buscar, $reemplazar)

if ($nuevo -ne $contenido) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ahConfig, $nuevo, $utf8NoBom)
    Write-Host "Guardado correctamente."
    
    # Verificar
    $ver = [System.IO.File]::ReadAllText($ahConfig, [System.Text.Encoding]::UTF8)
    $idx = $ver.IndexOf("SslAllow")
    Write-Host $ver.Substring($idx - 20, 350)
    
    Restart-Service FTPSVC -Force
    Write-Host "Estado: $((Get-Service FTPSVC).Status)"
} else {
    Write-Host "[ERROR] Patron no encontrado. Verificar manualmente."
    # Mostrar texto exacto alrededor de SslAllow para diagnostico
    $idx = $contenido.IndexOf("SslAllow")
    Write-Host "Texto actual:"
    Write-Host $contenido.Substring($idx - 20, 150)
}