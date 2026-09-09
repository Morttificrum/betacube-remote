<#
.SYNOPSIS
  Gera um instalador do Beta Cube Remote com a tag de uma loja/cliente já
  embutida (cria/associa a Entidade certa no GLPI automaticamente).

.DESCRIPTION
  Dispara o workflow build-betacube.yml no GitHub Actions passando o nome
  da loja, espera terminar (leva minutos, não horas -- só reempacota o
  instalador em cima do exe do fork já compilado) e baixa o resultado pra
  uma pasta local.

  Requer: GitHub CLI (gh) instalado e autenticado
  (https://cli.github.com/, depois "gh auth login").

.PARAMETER StoreName
  Nome da loja/cliente (ex: MBM). Só letras/números/hífen -- outros
  caracteres são removidos automaticamente.

.PARAMETER OutputDir
  Pasta onde salvar o instalador gerado. Padrão: .\instaladores

.EXAMPLE
  .\gerar-instalador-loja.ps1 -StoreName MBM
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$StoreName,

    [string]$OutputDir = ".\instaladores",

    [string]$Repo = "Morttificrum/betacube-remote",

    [string]$ForkTag = "betacube-build"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) não encontrado. Instale em https://cli.github.com/ e rode 'gh auth login' primeiro."
    exit 1
}

if (-not $StoreName) {
    $StoreName = Read-Host "Nome da loja/cliente (ex: MBM)"
}
$clean = ($StoreName -replace '[^A-Za-z0-9-]', '')
if ($clean -eq "") {
    Write-Error "Nome '$StoreName' não sobrou nada depois de tirar caracteres inválidos (só letras/números/hífen)."
    exit 1
}
if ($clean -ne $StoreName) {
    Write-Host "Nome ajustado pra '$clean' (só letras/números/hífen são permitidos)."
}
$StoreName = $clean

Write-Host "Disparando build do instalador pra loja '$StoreName'..."
gh workflow run build-betacube.yml --repo $Repo -f "store_name=$StoreName" -f "fork_tag=$ForkTag"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Start-Sleep -Seconds 8
$run = gh run list --repo $Repo --workflow=build-betacube.yml --limit 1 --json databaseId,status | ConvertFrom-Json | Select-Object -First 1
if (-not $run) {
    Write-Error "Não consegui encontrar o run recém-disparado."
    exit 1
}
$runId = $run.databaseId
Write-Host "Run: https://github.com/$Repo/actions/runs/$runId -- aguardando terminar (alguns minutos)..."

gh run watch $runId --repo $Repo --exit-status
if ($LASTEXITCODE -ne 0) {
    Write-Error "O build falhou. Veja o log: https://github.com/$Repo/actions/runs/$runId"
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}
Write-Host "Baixando instalador..."
gh run download $runId --repo $Repo --dir $OutputDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exe = Get-ChildItem -Path $OutputDir -Filter "*$StoreName*setup.exe" -Recurse -File | Select-Object -First 1
if ($exe) {
    # "gh run download" cria uma pasta com o mesmo nome do artefato (que é
    # o mesmo nome do .exe) contendo o arquivo -- move pra fora e limpa a
    # pasta, senão colide de nome com ela mesma.
    $finalPath = Join-Path $OutputDir $exe.Name
    $tempPath = Join-Path $OutputDir "_tmp_$($exe.Name)"
    Move-Item -Force $exe.FullName $tempPath
    if (Test-Path $finalPath) {
        Remove-Item -Recurse -Force $finalPath
    }
    Move-Item -Force $tempPath $finalPath
    Write-Host "Pronto: $finalPath"
} else {
    Write-Host "Build terminou, mas não achei o .exe automaticamente -- confira a pasta '$OutputDir'."
}
