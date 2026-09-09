# Extrai o payload "cru" de um MSI do RustDesk/Beta Cube Remote via
# `msiexec /a` (instalação administrativa -- só copia arquivo pro diretório
# indicado, não instala nada no sistema, não precisa admin/UAC) e deixa o
# resultado em .\rdpayload, do jeito que o NSIS (installer\betacube-installer.nsi)
# espera encontrar.
#
# Motivo de usar o MSI em vez do .exe portátil do release: ver comentário em
# build-betacube.yml. Resumo: o .exe portátil é um stub autoextraível que
# sempre extrai/roda a partir de %LOCALAPPDATA%\rustdesk (hardcoded), o MSI
# tem a build "crua" do Flutter direto.
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath
)

$ErrorActionPreference = "Stop"

$extractDir = Join-Path $PWD "msi-extract"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

$proc = Start-Process msiexec -ArgumentList "/a", "`"$MsiPath`"", "/qn", "TARGETDIR=`"$extractDir`"" -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Error "msiexec /a falhou com exit code $($proc.ExitCode)"
    exit 1
}

$mainExe = Get-ChildItem -Path $extractDir -Recurse -Filter "RustDesk.exe" | Select-Object -First 1
if (-not $mainExe) {
    Write-Error "RustDesk.exe não encontrado no MSI extraído (layout do MSI pode ter mudado)"
    exit 1
}

$payloadDir = $mainExe.DirectoryName
Write-Host "Payload extraído em: $payloadDir"

$dest = Join-Path $PWD "rdpayload"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Copy-Item -Path $payloadDir -Destination $dest -Recurse -Force

Write-Host "Payload copiado para: $dest"
Get-ChildItem $dest | Select-Object Name, Length | Format-Table -AutoSize
