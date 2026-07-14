<#
.SYNOPSIS
    Instalacao completa do SigeDash no servidor do cliente.
.DESCRIPTION
    Executa em sequencia:
      1. PostgreSQL 16  (banco de dados)
      2. SigeDash Backend  (API + PWA como Windows Service)
      3. SigeDash Agente   (coleta dados do Firebird)
      4. Cloudflare Tunnel (acesso externo HTTPS)
      5. Cria o usuario do cliente no sistema

    Todos os passos geram log em C:\SigeDash\install.log.

.PARAMETER NomeCliente
    Nome do cliente. Se omitido, detectado automaticamente via NOMEFANTASIA do banco Firebird.

.PARAMETER FdbPath
    Caminho completo para o arquivo .FDB do Sigecom no servidor.
    Padrao: C:\SIGECOM\SIGECOM.FDB (caminho padrao de instalacao do Sigecom)

.PARAMETER TunnelToken
    Token do tunel Cloudflare (obtido no painel Zero Trust antes de rodar este script).
    Deixe em branco para pular a instalacao do tunel (instale manualmente depois).

.PARAMETER SigeDashSenha
    Senha do banco PostgreSQL. Gerada automaticamente se omitida.

.EXAMPLE
    .\instalar-tudo.ps1 -TunnelToken "eyJhIjoiMT..."
    .\instalar-tudo.ps1 -FdbPath "D:\SIGECOM\SIGECOM.FDB" -TunnelToken "eyJhIjoiMT..."
    .\instalar-tudo.ps1 -NomeCliente "Amaral Ferragens" -TunnelToken "eyJhIjoiMT..."
#>
param(
    [string]$NomeCliente       = "",
    [string]$FdbPath           = "C:\SIGECOM\SIGECOM.FDB",

    [string]$TunnelToken       = "",
    [string]$SigeDashSenha     = ""
)

$ErrorActionPreference = "Stop"
$LOG_GERAL = "C:\SigeDash\install.log"
$SCRIPT_DIR = $PSScriptRoot

function Log($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    New-Item -ItemType Directory -Path "C:\SigeDash" -Force | Out-Null
    Add-Content $LOG_GERAL $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Titulo($msg) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Log ">>> $msg"
}

function Sucesso($msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
    Log "[OK] $msg"
}

function Falha($msg) {
    Write-Host "[ERRO] $msg" -ForegroundColor Red
    Log "[ERRO] $msg"
    exit 1
}

function CriarTunnelCloudflare($nomeCliente, $scriptDir) {
    $cfConfig = Join-Path $scriptDir "cf.json"
    if (-not (Test-Path $cfConfig)) {
        Log "cf.json nao encontrado - tunnel sera configurado manualmente."
        return $null
    }
    $cf      = Get-Content $cfConfig | ConvertFrom-Json
    $headers = @{ "Authorization" = "Bearer $($cf.apiToken)"; "Content-Type" = "application/json" }

    # Slug: "5 Estrelas Comercial" -> "5estrelas"
    $slug = ($nomeCliente -replace '[^a-zA-Z0-9]', '').ToLower()
    if ($slug.Length -gt 20) { $slug = $slug.Substring(0, 20) }
    $tunnelName = "sigedash-$slug"
    $hostname   = "$slug.$($cf.dominio)"

    Log "Criando tunnel Cloudflare: $tunnelName ..."

    # Cria o tunnel (segredo via CSPRNG, nao Get-Random)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $secretBytes = New-Object byte[] 32; $rng.GetBytes($secretBytes)
    $body = @{
        name          = $tunnelName
        tunnel_secret = [Convert]::ToBase64String($secretBytes)
    } | ConvertTo-Json

    try {
        $resp     = Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel" `
            -Method POST -Headers $headers -Body $body
        $tunnelId = $resp.result.id
        Log "Tunnel criado: $tunnelId"
    } catch {
        Log "AVISO: erro ao criar tunnel Cloudflare: $_"
        return $null
    }

    # Configura ingress (hostname -> localhost:5000)
    $ingressBody = @{
        config = @{
            ingress = @(
                @{ hostname = $hostname; service = "http://localhost:5000" },
                @{ service  = "http_status:404" }
            )
        }
    } | ConvertTo-Json -Depth 6
    try {
        Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel/$tunnelId/configurations" `
            -Method PUT -Headers $headers -Body $ingressBody | Out-Null
        Log "Ingress configurado: $hostname -> localhost:5000"
    } catch {
        Log "AVISO: erro ao configurar ingress: $_"
    }

    # Cria DNS CNAME
    $dnsBody = @{
        type    = "CNAME"
        name    = $slug
        content = "$tunnelId.cfargotunnel.com"
        proxied = $true
        ttl     = 1
    } | ConvertTo-Json
    try {
        Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/zones/$($cf.zoneId)/dns_records" `
            -Method POST -Headers $headers -Body $dnsBody | Out-Null
        Log "DNS criado: https://$hostname"
    } catch {
        Log "AVISO: erro ao criar DNS (pode ja existir): $_"
    }

    # Obtem token do tunnel
    try {
        $tokenResp = Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel/$tunnelId/token" `
            -Headers $headers
        Log "Token do tunnel obtido com sucesso."
        return @{ Token = $tokenResp.result; Url = "https://$hostname" }
    } catch {
        Log "AVISO: erro ao obter token do tunnel: $_"
        return $null
    }
}

function BuscarNomeFantasia($fdbPath) {
    $candidatos = @(
        "C:\Program Files\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files\Firebird\Firebird_3_0\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_3_0\bin\isql.exe"
    )
    $isql = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $isql) {
        Log "AVISO: isql.exe nao encontrado - informe -NomeCliente manualmente."
        return $null
    }
    $sqlFile = Join-Path $env:TEMP "sigedash_query.sql"
    @("SELECT NOMEFANTASIA FROM EMPRESA WHERE CODIGOEMPRESA = 1;", "EXIT;") |
        Out-File $sqlFile -Encoding ASCII
    try {
        $saida = & $isql -user SYSDBA -password masterkey $fdbPath -q -i $sqlFile 2>&1
        $nome  = $saida | Where-Object {
            $_ -and
            $_ -notmatch '^\s*$' -and
            $_ -notmatch '^NOMEFANTASIA' -and
            $_ -notmatch '^[= ]+$' -and
            $_ -notmatch '^Database:'
        } | Select-Object -First 1
        return ($nome -as [string]).Trim()
    } catch {
        Log "AVISO: erro ao consultar Firebird: $_"
        return $null
    } finally {
        Remove-Item $sqlFile -ErrorAction SilentlyContinue
    }
}

# Verifica privilegio de admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador (clique direito -> Executar como administrador)."
    exit 1
}

# Auto-detecta nome do cliente via Firebird se nao informado
if ([string]::IsNullOrWhiteSpace($NomeCliente)) {
    Log "NomeCliente nao informado — buscando NOMEFANTASIA no banco Firebird..."
    $NomeCliente = BuscarNomeFantasia $FdbPath
    if ([string]::IsNullOrWhiteSpace($NomeCliente)) {
        Falha "Nao foi possivel detectar o nome do cliente. Informe -NomeCliente manualmente."
    }
    Log "Nome detectado automaticamente: $NomeCliente"
}

# Gera senha do banco se nao informada
if ([string]::IsNullOrWhiteSpace($SigeDashSenha)) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 24; $rng.GetBytes($bytes)   # CSPRNG (nao Get-Random)
    $SigeDashSenha = [Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', ''
    $SigeDashSenha = ($SigeDashSenha + "Sd1!").Substring(0, 16)
    Log "Senha do banco gerada automaticamente."
}

Log ""
Log "=== Instalacao SigeDash - Cliente: $NomeCliente ==="
Log "FDB     : $FdbPath"
Write-Host "Senha PG: $SigeDashSenha" -ForegroundColor Yellow   # console apenas (segredo, fora do log)
Log ""

# ============================================================
Titulo "PASSO 1 - PostgreSQL 16"
# ============================================================
$scriptPg = Join-Path $SCRIPT_DIR "instalar-postgres.ps1"
if (-not (Test-Path $scriptPg)) { Falha "instalar-postgres.ps1 nao encontrado em $SCRIPT_DIR" }

try {
    & $scriptPg -SigeDashSenha $SigeDashSenha
    # exit 1 em script filho nao lanca excecao - checar $LASTEXITCODE explicitamente
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Falha "instalar-postgres.ps1 falhou com codigo $LASTEXITCODE"
    }
    Sucesso "PostgreSQL instalado e configurado."
} catch {
    Falha "Erro no PostgreSQL: $_"
}

# ============================================================
Titulo "PASSO 2 - SigeDash Backend"
# ============================================================
$scriptBack = Join-Path $SCRIPT_DIR "instalar-backend.ps1"
if (-not (Test-Path $scriptBack)) { Falha "instalar-backend.ps1 nao encontrado em $SCRIPT_DIR" }

try {
    & $scriptBack -PostgresSenha $SigeDashSenha -PublishDir $SCRIPT_DIR
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Falha "instalar-backend.ps1 falhou com codigo $LASTEXITCODE"
    }
    # Extrai a AdminKey do log de instalacao
    $adminKeyLine = Get-Content "C:\SigeDash\Backend\install.log" -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match "AdminKey\s*:" } | Select-Object -Last 1
    if ($adminKeyLine -match "AdminKey\s*:\s*(.+)$") {
        $AdminKey = $Matches[1].Trim()
        Log "AdminKey capturada do log do backend."
    } else {
        # Fallback: le direto do appsettings.Production.json
        $appsettings = Get-Content "C:\SigeDash\Backend\appsettings.Production.json" | ConvertFrom-Json
        $AdminKey    = $appsettings.AdminKey
        Log "AdminKey lida do appsettings.Production.json."
    }
    Sucesso "Backend instalado."
    Write-Host "AdminKey: $AdminKey" -ForegroundColor Yellow   # console apenas (segredo, fora do log)
} catch {
    Falha "Erro no backend: $_"
}

# ============================================================
Titulo "PASSO 3 - SigeDash Agente"
# ============================================================
# O agente agora e instalado via instalar-agente.ps1 (binarios + servico, nao-interativo).
# Os binarios ficam na subpasta 'agente' do pacote.
$scriptAgente = Join-Path $SCRIPT_DIR "instalar-agente.ps1"
$agenteSrc    = Join-Path $SCRIPT_DIR "agente"

if (-not (Test-Path $scriptAgente)) {
    Log "AVISO: instalar-agente.ps1 nao encontrado em $SCRIPT_DIR"
    Log "Instale o agente manualmente depois."
} elseif (-not (Test-Path (Join-Path $agenteSrc "SigeDash.Agente.exe"))) {
    Log "AVISO: binarios do agente nao encontrados em $agenteSrc"
    Log "O pacote pode ter sido gerado sem o agente. Instale manualmente depois."
} else {
    try {
        & $scriptAgente `
            -BackendUrl  "http://localhost:5000" `
            -AdminKey    $AdminKey `
            -ClienteNome $NomeCliente `
            -FdbPath     $FdbPath `
            -AgenteSrc   $agenteSrc
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Log "AVISO: instalar-agente.ps1 retornou codigo $LASTEXITCODE. Verifique manualmente."
        } else {
            Sucesso "Agente instalado e configurado."
        }
    } catch {
        Log "AVISO: erro ao instalar agente: $_"
        Log "Execute manualmente: instalar-agente.ps1"
    }
}

# ============================================================
Titulo "PASSO 4 - Cloudflare Tunnel"
# ============================================================
$TunnelUrl = ""

if ([string]::IsNullOrWhiteSpace($TunnelToken)) {
    Log "TunnelToken nao informado - tentando criar automaticamente via API Cloudflare..."
    $cfResult = CriarTunnelCloudflare $NomeCliente $SCRIPT_DIR
    if ($cfResult) {
        $TunnelToken = $cfResult.Token
        $TunnelUrl   = $cfResult.Url
        Sucesso "Tunnel Cloudflare criado: $TunnelUrl"
    }
}

if (-not [string]::IsNullOrWhiteSpace($TunnelToken)) {
    $scriptTunnel = Join-Path $SCRIPT_DIR "instalar-tunnel.ps1"
    if (-not (Test-Path $scriptTunnel)) { Falha "instalar-tunnel.ps1 nao encontrado em $SCRIPT_DIR" }
    try {
        & $scriptTunnel -TunnelToken $TunnelToken
        Sucesso "Cloudflare Tunnel instalado."
    } catch {
        Log "AVISO: erro no tunnel: $_"
        Log "Instale manualmente com: instalar-tunnel.ps1 -TunnelToken <TOKEN>"
    }
} else {
    Log "AVISO: tunnel nao configurado. Para instalar manualmente depois:"
    Log "  1. Execute .\configurar-cf.ps1 na maquina de desenvolvimento"
    Log "  2. Gere novo pacote com build-deploy.ps1"
    Log "  OU informe -TunnelToken ao executar instalar-tudo.ps1"
}

# ============================================================
Titulo "INSTALACAO CONCLUIDA"
# ============================================================
Log ""
Log "Resumo da instalacao:"
Log "  Cliente   : $NomeCliente"
Log "  Backend   : http://localhost:5000 (servico SigeDashBackend)"
Log "  Agente    : servico SigeDashAgente"
Log "  PostgreSQL: servico postgresql-x64-16"
if (-not [string]::IsNullOrWhiteSpace($TunnelToken)) {
    if (-not [string]::IsNullOrWhiteSpace($TunnelUrl)) {
        Log "  Tunnel    : $TunnelUrl (acesso externo HTTPS)"
    } else {
        Log "  Tunnel    : servico cloudflared ativo (verifique URL no painel Cloudflare)"
    }
}
Log ""
Write-Host "AdminKey para gerenciar clientes: $AdminKey" -ForegroundColor Yellow   # console apenas (segredo)
Log ""
Log "Log completo salvo em: $LOG_GERAL"
Log ""

# Destaque da URL do cliente
if (-not [string]::IsNullOrWhiteSpace($TunnelUrl)) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "  URL DO CLIENTE (compartilhe agora):" -ForegroundColor Green
    Write-Host ""
    Write-Host "  $TunnelUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Acesso pelo celular, tablet ou computador." -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Log "URL do cliente: $TunnelUrl"
}

Log "PROXIMOS PASSOS:"
Log "  1. Aguarde 30 minutos para o agente sincronizar os primeiros dados"
Log "  2. Envie a URL acima ao cliente para acesso pelo celular"
Log "  3. Faca login com as credenciais criadas automaticamente"