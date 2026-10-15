#Requires -Version 5
<#
.SYNOPSIS
Bateria de teste do Beta Cube Remote na VM Hyper-V BetaCubeTeste (checklist de 7 passos
do CLAUDE.md/AGENTS.md + checagem de "RustDesk" visivel + queda de rede), via PowerShell Direct.

Pre-requisitos (host): usuario nos "Administradores do Hyper-V" (token novo, depois de logoff/logon),
VM BetaCubeTeste ligada, credencial do guest em C:\Users\Morttificarum\.claude\projects\...\memory\
reference_betacubeteste_vm.md (NAO colocar senha neste arquivo -- o repo e publico).

STATUS: escrito em 2026-10-15, AINDA NAO EXECUTADO (sem acesso a VM na sessao em que foi escrito).
Corrija o que falhar na primeira execucao e registre no PEDIDOS.md.

Uso (cada fase imprime a evidencia; guarde a saida para o relatorio):
  $cred = Get-Credential betatest
  .\vm-battery.ps1 -Phase Prep      -Credential $cred
  .\vm-battery.ps1 -Phase Install   -Credential $cred -Installer C:\...\old-setup.exe        # passo 1: versao antiga
  .\vm-battery.ps1 -Phase Install   -Credential $cred -Installer C:\...\new-setup.exe        # por cima
  .\vm-battery.ps1 -Phase Verify    -Credential $cred                                        # passos 2-5 + rebrand
  .\vm-battery.ps1 -Phase Reboot    -Credential $cred -Count 5                               # passo 7 (N reinicios)
  .\vm-battery.ps1 -Phase NetCycle  -Credential $cred                                        # queda/volta de rede
  .\vm-battery.ps1 -Phase Screenshot -Credential $cred                                       # janela/bandeja (sessao interativa)

Passo 6 (conexao remota com a janela fechada) precisa de um cliente conectando de fora:
o script so confirma o proxy usado antes (rendezvous_reachable=1 no bridge); a conexao em si
e feita pelo Fernando/Claude com outro Beta Cube Remote e anexada como evidencia.
#>
param(
    [Parameter(Mandatory)][ValidateSet('Prep','Install','Verify','Reboot','NetCycle','Screenshot')][string]$Phase,
    [Parameter(Mandatory)][pscredential]$Credential,
    [string]$VmName = 'BetaCubeTeste',
    [string]$Installer,
    [int]$Count = 1,
    [string]$AppName = 'Beta Cube Remote',
    [string]$BridgeDevicesUrl = 'http://remote.betacube.com.br:21114/internal/devices',
    [string]$OutDir = "$env:TEMP\vm-battery"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Wait-Guest([int]$TimeoutSec = 300) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try { Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock { 1 } -ErrorAction Stop | Out-Null; return }
        catch { Start-Sleep 5 }
    }
    throw "Guest nao respondeu em $TimeoutSec s (PowerShell Direct)."
}
function Invoke-Guest([scriptblock]$Block, $ArgList = @()) {
    Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock $Block -ArgumentList $ArgList
}
function Get-BridgeState([string]$HostName) {
    try {
        $d = Invoke-RestMethod -Uri $BridgeDevicesUrl -TimeoutSec 20
        $d | Where-Object { $_.hostname -eq $HostName } | Sort-Object last_seen_at -Descending | Select-Object -First 1 `
            hostname, rustdesk_id, last_seen_at, rendezvous_reachable, rendezvous_reachable_at
    } catch { "bridge inacessivel: $($_.Exception.Message)" }
}

$vm = Get-VM -Name $VmName
if ($vm.State -ne 'Running') { Start-VM -Name $VmName | Out-Null }

switch ($Phase) {
    'Prep' {
        Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false   # armadilha: checkpoints automaticos descartam alteracoes
        Enable-VMIntegrationService -VMName $VmName -Name 'Interface de Serviço de Convidado' -ErrorAction SilentlyContinue
        Wait-Guest
        Get-VM -Name $VmName | Select-Object Name, State, Generation, MemoryAssigned, ProcessorCount, AutomaticCheckpointsEnabled | Format-List
        Invoke-Guest {
            [pscustomobject]@{
                Host = $env:COMPUTERNAME; User = whoami
                OS   = (Get-CimInstance Win32_OperatingSystem).Caption
                UAC  = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System).EnableLUA
                Rede = (Test-NetConnection remote.betacube.com.br -Port 21116 -WarningAction SilentlyContinue).TcpTestSucceeded
            }
        } | Format-List
    }
    'Install' {
        if (-not $Installer -or -not (Test-Path $Installer)) { throw "-Installer invalido: $Installer" }
        Wait-Guest
        $name = Split-Path $Installer -Leaf
        Invoke-Guest { New-Item -ItemType Directory -Force C:\Temp | Out-Null }
        # PSSession (PowerShell Direct) em vez de Copy-VMFile: nao depende do servico de integracao "Interface de Servico de Convidado"
        $s = New-PSSession -VMName $VmName -Credential $Credential
        try { Copy-Item -Path $Installer -Destination "C:\Temp\$name" -ToSession $s -Force } finally { Remove-PSSession $s }
        # O NSIS termina com um MessageBox MB_OK sem /SD (nao e silencioso de verdade): em sessao nao interativa ele
        # trava. Espera o fim real da instalacao (uninstall.exe escrito + servico existente) e encerra o setup.
        Invoke-Guest { param($n)
            $p = Start-Process "C:\Temp\$n" -ArgumentList '/S' -PassThru
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 420) {
                if ((Test-Path 'C:\Program Files\Beta Cube Remote\uninstall.exe') -and ($sw.Elapsed.TotalSeconds -gt 60)) {
                    Start-Sleep 20; "Setup preso no MessageBox final ('instalado com sucesso') -- encerrando setup apos conclusao dos passos"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; break }
                Start-Sleep 5 }
            "Tempo ate concluir: $([int]$sw.Elapsed.TotalSeconds)s; HasExited=$($p.HasExited)"
        } -ArgList $name
        Start-Sleep 20   # --silent-install roda em processo filho depois do NSIS "concluir"
        "Instalado: $name"
    }
    'Verify' {
        Wait-Guest
        $r = Invoke-Guest {
            param($app)
            $sc = (& sc.exe query $app) -join "`n"       # SEMPRE sc.exe, nunca sc puro
            $lnks = @(Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu','C:\Users\Public\Desktop',"$env:USERPROFILE\Desktop","$env:APPDATA\Microsoft\Windows\Start Menu" -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'Beta Cube|RustDesk' } | Select-Object -ExpandProperty FullName)
            $dir = Join-Path ${env:ProgramFiles} $app
            $files = if (Test-Path $dir) { Get-ChildItem $dir -Recurse -File | Select-Object -ExpandProperty FullName } else { @() }
            $rd = @($files | Where-Object { $_ -match 'rustdesk' })
            $ver = if (Test-Path "$dir\$app.exe") { (Get-Item "$dir\$app.exe").VersionInfo | Select-Object ProductName, CompanyName, FileDescription, OriginalFilename } else { 'exe nao encontrado' }
            [pscustomobject]@{
                Servico           = $sc
                Atalhos           = $lnks
                QtdAtalhos        = $lnks.Count                       # passo 2: tem que ser 1 (0 se maquina de loja com STORE_NAME)
                ArquivosInstalados= $files.Count
                ArquivosRustDesk  = $rd                                # rebrand: deve ser vazio
                VersionInfo       = $ver
                Impressoras       = @(Get-Printer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                DriversImpressora = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                ServicosRustDesk  = @(Get-Service | Where-Object { $_.DisplayName -match 'rustdesk' -or $_.Name -match 'rustdesk' } | Select-Object -ExpandProperty Name)
                ProgramDataRD     = @(Get-ChildItem 'C:\ProgramData' -Directory -ErrorAction SilentlyContinue | Where-Object Name -match 'rustdesk' | Select-Object -ExpandProperty FullName)
                Uninstall         = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                                       Where-Object { $_.DisplayName -match 'Beta Cube|RustDesk' } | Select-Object DisplayName, Publisher, DisplayVersion)
                Config            = (Get-Content 'C:\ProgramData\Beta Cube Remote\config\*.toml' -ErrorAction SilentlyContinue | Select-String 'rendezvous|relay|api-server|preset-note' | ForEach-Object { $_.Line })
                Processos         = @(Get-Process | Where-Object { $_.Name -match 'Beta Cube|rustdesk' } | Select-Object Name, Id, MainWindowTitle)
                Host              = $env:COMPUTERNAME
            }
        } -ArgList $AppName
        $r | Format-List
        "--- Bridge (passo 5 / hbbs):"
        Get-BridgeState $r.Host | Format-List
        $r | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir "verify-$(Get-Date -Format yyyyMMdd-HHmmss).json") -Encoding UTF8
    }
    'Reboot' {
        for ($i = 1; $i -le $Count; $i++) {
            "=== Reinicio $i/$Count"
            Restart-VM -Name $VmName -Force
            Start-Sleep 20
            Wait-Guest 600
            Start-Sleep 60                       # tempo para o servico subir e registrar sozinho, sem clique
            $s = Invoke-Guest { param($app) [pscustomobject]@{ Host = $env:COMPUTERNAME; Servico = ((& sc.exe query $app) -join ' ') } } -ArgList $AppName
            $s | Format-List
            Get-BridgeState $s.Host | Format-List   # esperado: rendezvous_reachable = 1 e last_seen_at recente
        }
    }
    'NetCycle' {
        Wait-Guest
        $h = (Invoke-Guest { $env:COMPUTERNAME })
        $vmNic = Get-VMNetworkAdapter -VMName $VmName
        "=== Rede DESCONECTADA"
        Disconnect-VMNetworkAdapter -VMName $VmName
        Start-Sleep 90
        "=== Rede RECONECTADA"
        Connect-VMNetworkAdapter -VMNetworkAdapter $vmNic -SwitchName $vmNic.SwitchName
        Start-Sleep 90
        Get-BridgeState $h | Format-List       # esperado: volta sozinho, sem clique
    }
    'Screenshot' {
        # PowerShell Direct nao tem desktop: usa Tarefa Agendada interativa (sessao 1), removida ao fim.
        Wait-Guest
        $b64 = Invoke-Guest {
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing
            $out = 'C:\Temp\shot.png'; Remove-Item $out -ErrorAction SilentlyContinue
            $script = 'Add-Type -AssemblyName System.Windows.Forms,System.Drawing;$b=[Windows.Forms.SystemInformation]::VirtualScreen;$bmp=New-Object Drawing.Bitmap $b.Width,$b.Height;[Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location,[Drawing.Point]::Empty,$b.Size);$bmp.Save("C:\Temp\shot.png")'
            Set-Content C:\Temp\shot.ps1 $script
            $a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Temp\shot.ps1'
            $pr = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
            Register-ScheduledTask -TaskName BcShot -Action $a -Principal $pr -Force | Out-Null
            Start-ScheduledTask -TaskName BcShot; Start-Sleep 8
            Unregister-ScheduledTask -TaskName BcShot -Confirm:$false
            if (Test-Path $out) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($out)) } else { '' }
        }
        if ($b64) { $f = Join-Path $OutDir "shot-$(Get-Date -Format yyyyMMdd-HHmmss).png"; [IO.File]::WriteAllBytes($f, [Convert]::FromBase64String($b64)); "Screenshot: $f" }
        else { "Sem screenshot (nenhuma sessao interativa logada no guest?)" }
    }
}
