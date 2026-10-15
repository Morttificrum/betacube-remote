#Requires -Version 5
<#
.SYNOPSIS
Dispara uma ação na VM BetaCubeTeste via a Tarefa Agendada
"BetaCubeElevRunner" (SYSTEM), sem precisar de admin nesta sessão.
Pré-requisito: register-vm-test-task.ps1 já ter sido rodado como admin.

.PARAMETER Action
Start | Stop | Restart | NetDown | NetUp | Status | IP | RemoveTask

.EXAMPLE
.\invoke-vm-action.ps1 -Action Status
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('Start','Stop','Restart','NetDown','NetUp','Status','IP','RemoveTask')]
    [string]$Action,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = "Stop"

$autoDir     = "C:\ProgramData\BetaCubeAutomation"
$requestPath = Join-Path $autoDir "request.json"
$resultPath  = Join-Path $autoDir "result.json"
$taskName    = "BetaCubeElevRunner"

if ($Action -ne 'RemoveTask' -and -not (Test-Path $autoDir)) {
    Write-Error "Pasta $autoDir não existe -- rode register-vm-test-task.ps1 como admin antes."
    exit 1
}

Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue

$requestId = [guid]::NewGuid().ToString()
[ordered]@{ action = $Action; requestId = $requestId } | ConvertTo-Json | Set-Content -Path $requestPath -Encoding UTF8

schtasks /run /tn $taskName | Out-Null

# Não confia no "Status" do schtasks (task on-demand curta pode já
# reportar "Pronto" antes de terminar de fato) -- poll direto no
# result.json até o requestId bater.
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$matched = $false
do {
    Start-Sleep -Milliseconds 800
    if (Test-Path $resultPath) {
        try {
            $peek = Get-Content $resultPath -Raw | ConvertFrom-Json
            if ($peek.requestId -eq $requestId) { $matched = $true }
        } catch {}
    }
} while (-not $matched -and (Get-Date) -lt $deadline)

if ($Action -eq 'RemoveTask') {
    $confirmPath = "C:\ProgramData\BetaCubeAutomation_removed.json"
    if (Test-Path $confirmPath) {
        Get-Content $confirmPath -Raw | Write-Output
        Remove-Item $confirmPath -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Sem confirmação de remoção -- verifique manualmente (schtasks /query /tn $taskName)."
    }
    exit 0
}

if (-not (Test-Path $resultPath)) {
    Write-Error "Sem result.json depois de $TimeoutSeconds s -- tarefa pode não ter rodado (confirme UAC/registro)."
    exit 1
}

$result = Get-Content $resultPath -Raw | ConvertFrom-Json
if ($result.requestId -ne $requestId) {
    Write-Warning "result.json é de outra requisição (concorrência?) -- resultado pode ser stale."
}
$result | ConvertTo-Json -Depth 5
if (-not $result.success) { exit 1 }
