<#
.SYNOPSIS
    Configura as credenciais do Cloudflare para criacao automatica de tunnels.
.DESCRIPTION
    Salva API Token, Account ID e Zone ID em deploy\cf.json (gitignored).
    Execute UMA VEZ na maquina do desenvolvedor. O build-deploy.ps1 inclui
    o cf.json em todos os pacotes gerados, tornando a instalacao 100% automatica.

    Permissoes necessarias no token:
      - Cloudflare Tunnel: Edit
      - DNS: Edit

.PARAMETER Dominio
    Dominio raiz no Cloudflare (ex: sigedash.com.br).
    Os clientes acessarao via {slug}.{dominio}   (ex: 5estrelas.sigedash.com.br).
.EXAMPLE
    .\configurar-cf.ps1
    .\configurar-cf.ps1 -Dominio "sigedash.com.br"
#>
param(
    [string]$Dominio = "sigedash.com.br"
)

$ErrorActionPreference = "Stop"
$CF_CONFIG = Join-Path $PSScriptRoot "deploy\cf.json"

function Log($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  SigeDash - Configuracao do Cloudflare" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""
Log "As credenciais serao salvas em: $CF_CONFIG" DarkGray
Log "Esse arquivo e gitignored - nunca sera versionado." DarkGray
Write-Host ""
Log "Gere um API Token em: https://dash.cloudflare.com/profile/api-tokens"
Log "Permissoes necessarias: Cloudflare Tunnel:Edit + DNS:Edit"
Write-Host ""

$tokenSec   = Read-Host "API Token do Cloudflare (nao sera exibido)" -AsSecureString
$tokenPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSec))

# Remove caracteres de controle invisiveis que podem vir ao colar o token
$tokenPlain = ($tokenPlain -replace '[\x00-\x1F\x7F]', '').Trim()

if ([string]::IsNullOrWhiteSpace($tokenPlain)) {
    Log "ERRO: token nao informado." Red; exit 1
}

$headers = @{ "Authorization" = "Bearer $tokenPlain"; "Content-Type" = "application/json" }

# Valida token
Write-Host ""
Log "Validando token..." DarkGray
try {
    $verify = Invoke-RestMethod "https://api.cloudflare.com/client/v4/user/tokens/verify" -Headers $headers
    if (-not $verify.success) { throw "Token invalido" }
    Log "Token valido." Green
} catch {
    Log "ERRO: token invalido ou sem permissao - $_" Red; exit 1
}

# Descobre Account ID automaticamente
Log "Buscando Account ID..." DarkGray
$accountId = ""
try {
    $accounts  = Invoke-RestMethod "https://api.cloudflare.com/client/v4/accounts" -Headers $headers
    $account   = $accounts.result | Select-Object -First 1
    $accountId = $account.id
    if ($accountId) {
        Log "Account: $($account.name) ($accountId)" Green
    }
} catch {}

# Fallback: solicita manualmente se nao encontrou
if ([string]::IsNullOrWhiteSpace($accountId)) {
    Log "Nao foi possivel detectar o Account ID automaticamente." Yellow
    Log "Encontre em: dash.cloudflare.com -> seu dominio -> lateral direita -> API -> Account ID"
    $accountId = (Read-Host "Account ID").Trim()
    if ([string]::IsNullOrWhiteSpace($accountId)) {
        Log "ERRO: Account ID nao informado." Red; exit 1
    }
    Log "Account ID informado: $accountId" Green
}

# Descobre Zone ID pelo dominio
Log "Buscando Zone ID para '$Dominio'..." DarkGray
try {
    $zones  = Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones?name=$Dominio" -Headers $headers
    if (-not $zones.result -or $zones.result.Count -eq 0) {
        throw "Dominio '$Dominio' nao encontrado na conta Cloudflare."
    }
    $zone   = $zones.result[0]
    $zoneId = $zone.id
    Log "Zone: $($zone.name) ($zoneId)" Green
} catch {
    Log "ERRO: $_" Red
    Log "Verifique se o dominio '$Dominio' esta cadastrado nessa conta Cloudflare." Yellow
    exit 1
}

# Salva cf.json
New-Item -ItemType Directory -Path (Split-Path $CF_CONFIG) -Force | Out-Null
@{
    apiToken  = $tokenPlain
    accountId = $accountId
    zoneId    = $zoneId
    dominio   = $Dominio
} | ConvertTo-Json | Set-Content $CF_CONFIG -Encoding UTF8

$tokenPlain = $null
[GC]::Collect()

Log "Configuracao salva em: $CF_CONFIG" Green
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Pronto!" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Log "Execute build-deploy.ps1 para gerar o pacote com o cf.json incluso."
Log "A instalacao no cliente sera 100% automatica - sem parametros."
Write-Host ""
