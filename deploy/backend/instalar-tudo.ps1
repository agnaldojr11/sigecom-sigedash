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
    Nome do cliente (ex: "Amaral Ferragens"). Usado para criar o usuario no sistema.

.PARAMETER FdbPath
    Caminho completo para o arquivo .FDB do Sigecom no servidor.
    Padrao: C:\SIGECOM\SIGECOM.FDB (caminho padrao de instalacao do Sigecom)

.PARAMETER TunnelToken
    Token do tunel Cloudflare (obtido no painel Zero Trust antes de rodar este script).
    Deixe em branco para pular a instalacao do tunel (instale manualmente depois).

.PARAMETER SigeDashSenha
    Senha do banco PostgreSQL. Gerada automaticamente se omitida.

.PARAMETER AgenteInstallerDir
    Pasta onde esta o SigeDashAgente-Setup.exe. Padrao: mesma pasta deste script.

.EXAMPLE
    .\instalar-tudo.ps1 -NomeCliente "Amaral Ferragens" -TunnelToken "eyJhIjoiMT..."
    .\instalar-tudo.ps1 -NomeCliente "Amaral Ferragens" -FdbPath "D:\SIGECOM\SIGECOM.FDB" -TunnelToken "eyJhIjoiMT..."
#>
param(
    [Parameter(Mandatory)]
    [string]$NomeCliente,

    [string]$FdbPath           = "C:\SIGECOM\SIGECOM.FDB",

    [string]$TunnelToken       = "",
    [string]$SigeDashSenha     = "",
    [string]$AgenteInstallerDir = $PSScriptRoot
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

# Verifica privilegio de admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador (clique direito -> Executar como administrador)."
    exit 1
}

# Gera senha do banco se nao informada
if ([string]::IsNullOrWhiteSpace($SigeDashSenha)) {
    $bytes        = 1..12 | ForEach-Object { [byte](Get-Random -Max 256) }
    $SigeDashSenha = [Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', '' | Select-Object -First 1
    $SigeDashSenha = ($SigeDashSenha + "Sd1!")[0..15] -join ''
    Log "Senha do banco gerada automaticamente."
}

Log ""
Log "=== Instalacao SigeDash - Cliente: $NomeCliente ==="
Log "FDB     : $FdbPath"
Log "Senha PG: $SigeDashSenha"
Log ""

# ============================================================
Titulo "PASSO 1 - PostgreSQL 16"
# ============================================================
$scriptPg = Join-Path $SCRIPT_DIR "instalar-postgres.ps1"
if (-not (Test-Path $scriptPg)) { Falha "instalar-postgres.ps1 nao encontrado em $SCRIPT_DIR" }

try {
    & $scriptPg -SigeDashSenha $SigeDashSenha
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
    $resultBack = & $scriptBack -PostgresSenha $SigeDashSenha -PublishDir $SCRIPT_DIR
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
    Sucesso "Backend instalado. AdminKey: $AdminKey"
} catch {
    Falha "Erro no backend: $_"
}

# ============================================================
Titulo "PASSO 3 - SigeDash Agente"
# ============================================================
$agenteSetup = Get-ChildItem $AgenteInstallerDir -Filter "SigeDashAgente-Setup*.exe" |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $agenteSetup) {
    Log "AVISO: SigeDashAgente-Setup.exe nao encontrado em $AgenteInstallerDir"
    Log "Instale o agente manualmente e depois execute:"
    Log "  configurar-cliente.ps1 -BackendUrl http://localhost:5000 -AdminKey '$AdminKey' -ClienteNome '$NomeCliente' -FdbPath '$FdbPath'"
} else {
    Log "Executando instalador do agente: $($agenteSetup.FullName)"
    $proc = Start-Process -FilePath $agenteSetup.FullName -ArgumentList "/SILENT" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Log "AVISO: instalador do agente retornou codigo $($proc.ExitCode). Verifique manualmente."
    } else {
        Sucesso "Agente instalado."
    }

    # Configura o agente
    $scriptConf = Join-Path $SCRIPT_DIR "configurar-cliente.ps1"
    if (-not (Test-Path $scriptConf)) {
        $scriptConf = "C:\Program Files\SistemasBr\SigeDash\configurar-cliente.ps1"
    }
    if (Test-Path $scriptConf) {
        try {
            & $scriptConf `
                -BackendUrl "http://localhost:5000" `
                -AdminKey $AdminKey `
                -ClienteNome $NomeCliente `
                -FdbPath $FdbPath
            Sucesso "Agente configurado."
        } catch {
            Log "AVISO: erro ao configurar agente: $_"
            Log "Execute manualmente: configurar-cliente.ps1"
        }
    }
}

# ============================================================
Titulo "PASSO 4 - Cloudflare Tunnel"
# ============================================================
if ([string]::IsNullOrWhiteSpace($TunnelToken)) {
    Log "Token do tunel nao informado - pulando instalacao do tunnel."
    Log ""
    Log "Para instalar depois, execute:"
    Log "  .\instalar-tunnel.ps1 -TunnelToken <TOKEN>"
    Log ""
    Log "Instrucoes para obter o token:"
    Log "  1. Acesse https://one.dash.cloudflare.com"
    Log "  2. Zero Trust -> Networks -> Tunnels -> Create a tunnel"
    Log "  3. Nome: sigedash-$(($NomeCliente -replace '[^a-zA-Z0-9]', '').ToLower())"
    Log "  4. Service: HTTP | URL: localhost:5000"
    Log "  5. Copie o token e execute instalar-tunnel.ps1"
} else {
    $scriptTunnel = Join-Path $SCRIPT_DIR "instalar-tunnel.ps1"
    if (-not (Test-Path $scriptTunnel)) { Falha "instalar-tunnel.ps1 nao encontrado em $SCRIPT_DIR" }

    try {
        & $scriptTunnel -TunnelToken $TunnelToken
        Sucesso "Cloudflare Tunnel instalado."
    } catch {
        Log "AVISO: erro no tunnel: $_"
        Log "Instale manualmente com: instalar-tunnel.ps1 -TunnelToken <TOKEN>"
    }
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
    Log "  Tunnel    : servico cloudflared (acesso externo via Cloudflare)"
}
Log ""
Log "AdminKey para gerenciar clientes: $AdminKey"
Log ""
Log "Log completo salvo em: $LOG_GERAL"
Log ""
Log "PROXIMOS PASSOS:"
Log "  1. Aguarde 30 minutos para o agente sincronizar os primeiros dados"
Log "  2. Acesse a URL do tunel Cloudflare pelo celular"
Log "  3. Faca login com as credenciais criadas automaticamente"