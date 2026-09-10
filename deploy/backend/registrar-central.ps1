<#
.SYNOPSIS
    Registra este cliente na SigeDash Central e liga a telemetria.
.DESCRIPTION
    Chama o endpoint idempotente POST /telemetria/registrar da Central (autenticado pela chave de
    provisionamento do central.json), recebe a ChaveTelemetria e grava o bloco "Central" no
    appsettings.Production.json do backend, reiniciando o servico para a telemetria comecar.

    Idempotente: rodar de novo com o mesmo Nome/CNPJ devolve a MESMA chave (nao duplica na Central).
    Nao-fatal: se o central.json faltar ou a Central estiver fora, apenas AVISA (nao derruba o install).
.PARAMETER Nome
    Nome do cliente (empresa).
.PARAMETER Cnpj
    CNPJ do cliente (identidade forte; evita duplicar se o nome for digitado diferente).
.PARAMETER BackendDir
    Pasta do backend. Padrao: C:\SigeDash\Backend
.PARAMETER ScriptDir
    Pasta onde esta o central.json. Padrao: a pasta deste script.
#>
param(
    [Parameter(Mandatory)][string]$Nome,
    [string]$Cnpj       = "",
    [string]$BackendDir = "C:\SigeDash\Backend",
    [string]$ScriptDir  = $PSScriptRoot
)

function LogC($m) { Write-Host "[central] $m" }

$centralCfg = Join-Path $ScriptDir "central.json"
if (-not (Test-Path $centralCfg)) {
    LogC "central.json ausente - telemetria NAO configurada (cliente nao aparecera na Central)."
    return
}

try {
    $cfg = Get-Content $centralCfg -Raw | ConvertFrom-Json
} catch {
    LogC "AVISO: central.json invalido: $_"
    return
}
$url = ("" + $cfg.Url).TrimEnd('/')
$bootstrap = "" + $cfg.ChaveBootstrap
if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($bootstrap)) {
    LogC "AVISO: central.json sem Url/ChaveBootstrap - pulando registro."
    return
}

# 1) Registra na Central (idempotente)
LogC "Registrando '$Nome' na Central..."
$body = @{ nome = $Nome; cnpj = $Cnpj } | ConvertTo-Json -Compress
$headers = @{ "X-Bootstrap-Key" = $bootstrap; "Content-Type" = "application/json" }
try {
    $resp = Invoke-RestMethod "$url/telemetria/registrar" -Method POST -Headers $headers -Body $body -TimeoutSec 30
} catch {
    LogC "AVISO: falha ao registrar na Central: $_"
    LogC "A telemetria pode ser ligada depois rodando este script novamente."
    return
}
$chave = "" + $resp.chaveTelemetria
if ([string]::IsNullOrWhiteSpace($chave)) { LogC "AVISO: Central nao retornou ChaveTelemetria."; return }
LogC ("Registrado (" + $(if ($resp.novo) { "novo" } else { "ja existia" }) + "). Chave obtida.")

# 2) Grava o bloco Central no appsettings.Production.json (preservando o resto)
$appPath = Join-Path $BackendDir "appsettings.Production.json"
if (-not (Test-Path $appPath)) { LogC "AVISO: $appPath nao encontrado - nao foi possivel gravar a chave."; return }

try {
    $json = Get-Content $appPath -Raw | ConvertFrom-Json
} catch {
    LogC "AVISO: appsettings.Production.json invalido - abortando gravacao."
    return
}

$central = [ordered]@{ Url = $url; ChaveTelemetria = $chave; IntervaloMin = 3 }
# Substitui/insere a propriedade "Central" sem perder as demais.
$json.PSObject.Properties.Remove("Central") | Out-Null
$json | Add-Member -NotePropertyName "Central" -NotePropertyValue $central

$json | ConvertTo-Json -Depth 12 | Set-Content $appPath -Encoding UTF8
LogC "appsettings.Production.json atualizado (bloco Central)."

# 3) Reinicia o backend para a telemetria comecar
try {
    Restart-Service "SigeDashBackend" -ErrorAction Stop
    LogC "Servico SigeDashBackend reiniciado - telemetria ativa."
} catch {
    LogC "AVISO: nao consegui reiniciar o SigeDashBackend ($_). Reinicie manualmente."
}
