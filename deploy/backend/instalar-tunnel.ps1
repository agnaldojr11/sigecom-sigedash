<#
.SYNOPSIS
    Instala o Cloudflare Tunnel como Windows Service no servidor do cliente.
.DESCRIPTION
    O Cloudflare Tunnel expoe o backend local (http://localhost:5000) com HTTPS
    para o exterior, sem precisar de IP fixo ou abrir portas no roteador.

    PRE-REQUISITO: crie o tunel no painel Cloudflare antes de rodar este script.
    Veja as instrucoes no final deste arquivo (Get-Help .\instalar-tunnel.ps1 -Full).

.PARAMETER TunnelToken
    Token do tunel gerado no painel Cloudflare Zero Trust.
    Painel -> Zero Trust -> Networks -> Tunnels -> seu tunel -> Configure -> token.

.PARAMETER InstallDir
    Pasta de instalacao do cloudflared. Padrao: C:\SigeDash\Tunnel

.EXAMPLE
    .\instalar-tunnel.ps1 -TunnelToken "eyJhIjoiMT..."

.NOTES
    Como criar o tunel no Cloudflare (fazer antes de rodar o script):

    1. Acesse https://dash.cloudflare.com e crie uma conta gratuita (se nao tiver)
    2. Acesse Zero Trust -> Networks -> Tunnels -> "Create a tunnel"
    3. Escolha "Cloudflared" como conector
    4. Nome sugerido: sigedash-[nome-do-cliente]  (ex: sigedash-amaral)
    5. Em "Public Hostname":
       - Subdomain: [nome-do-cliente]  (ex: amaral)
       - Domain: seu dominio (ex: sigedash.com.br)
            OU deixe o dominio padrao *.cfargotunnel.com para um URL automatico
       - Service: HTTP  |  URL: localhost:5000
    6. Salve o tunel. Copie o token exibido na tela de instalacao.
    7. Execute este script com o token copiado.
#>
param(
    [Parameter(Mandatory)]
    [string]$TunnelToken,

    [string]$InstallDir = "C:\SigeDash\Tunnel"
)

$ErrorActionPreference = "Stop"

$SVC_NAME      = "cloudflared"
$CLOUDFLARED   = Join-Path $InstallDir "cloudflared.exe"
$DOWNLOAD_URL  = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$LOG_FILE      = Join-Path $InstallDir "tunnel-install.log"

function Log($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

# Verifica privilegio de admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

Log "=== SigeDash - Instalacao do Cloudflare Tunnel ==="
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Para e remove servico existente
$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if ($svc) {
    Log "Servico $SVC_NAME encontrado - removendo versao anterior..."
    Stop-Service $SVC_NAME -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    # Continue evita que stderr do cloudflared.exe vire excecao com ErrorActionPreference=Stop
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $CLOUDFLARED service uninstall 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP
    Log "Servico removido."
}

# Baixa cloudflared.exe se necessario
if (-not (Test-Path $CLOUDFLARED)) {
    Log "Baixando cloudflared.exe..."
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($DOWNLOAD_URL, $CLOUDFLARED)
        Log "Download concluido: $CLOUDFLARED"
    } catch {
        Log "ERRO ao baixar cloudflared: $_"
        Log "Baixe manualmente em: https://github.com/cloudflare/cloudflared/releases/latest"
        Log "Salve como: $CLOUDFLARED"
        exit 1
    }
} else {
    Log "cloudflared.exe ja existe em $CLOUDFLARED"
}

# Verifica versao
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$versao = & $CLOUDFLARED --version 2>&1
$ErrorActionPreference = $prevEAP
Log "Versao: $versao"

# Instala como Windows Service com o token do tunel
Log "Instalando servico $SVC_NAME com o token do tunel..."
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$resultado = & $CLOUDFLARED service install $TunnelToken 2>&1
$ErrorActionPreference = $prevEAP
Log "Resultado: $resultado"

# Verifica se o servico foi registrado
$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if (-not $svc) {
    Log "ERRO: servico $SVC_NAME nao foi criado. Verifique o token e tente novamente."
    exit 1
}

# Inicia o servico
Log "Iniciando servico $SVC_NAME..."
Start-Service $SVC_NAME -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$svc = Get-Service $SVC_NAME
Log "Status do servico: $($svc.Status)"

if ($svc.Status -ne "Running") {
    Log "AVISO: servico nao esta em Running. Verifique o Event Viewer -> Logs do Windows -> Aplicativo"
    Log "Erro comum: token invalido ou expirado. Gere um novo token no painel Cloudflare."
    exit 1
}

# Configura startup automatico
Set-Service $SVC_NAME -StartupType Automatic | Out-Null
Log "Startup automatico configurado."

# Resumo
Log ""
Log "=== Cloudflare Tunnel instalado! ==="
Log "Servico : $SVC_NAME (automatico)"
Log ""
Log "A URL publica do cliente esta no painel Cloudflare:"
Log "  Zero Trust -> Networks -> Tunnels -> seu tunel -> Public Hostnames"
Log ""
Log "Compartilhe essa URL com o cliente para acesso ao SigeDash."
Log "Exemplo: https://amaral.sigedash.com.br"
Log ""
Log "IMPORTANTE: o acesso so funciona enquanto o servidor do cliente estiver"
Log "ligado e com internet ativa."