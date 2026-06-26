<#
.SYNOPSIS
    Verifica e aplica atualizacoes automaticas do SigeDash Backend.
.DESCRIPTION
    - Consulta GitHub Releases para verificar se ha versao mais nova
    - Compara com a versao instalada (version.txt)
    - Baixa, para o servico, atualiza e reinicia automaticamente
.PARAMETER InstallDir
    Pasta de instalacao do backend. Padrao: C:\SigeDash\Backend
.PARAMETER AgenteDir
    Pasta de instalacao do agente. Padrao: C:\Program Files\SistemasBr\SigeDash
.PARAMETER Repo
    Repositorio GitHub no formato "dono/repo".
.PARAMETER Forcar
    Aplica a atualizacao mesmo se a versao for a mesma.
.EXAMPLE
    .\atualizar.ps1
    .\atualizar.ps1 -Forcar
#>
param(
    [string]$InstallDir = "C:\SigeDash\Backend",
    [string]$AgenteDir  = "C:\Program Files\SistemasBr\SigeDash",
    [string]$Repo       = "sistemasbr/sigecom-sigedash",
    [switch]$Forcar
)

$ErrorActionPreference = "Stop"
$SVC_NAME   = "SigeDashBackend"
$SVC_AGENTE = "SigeDashAgente"
$VERSION_TXT = Join-Path $InstallDir "version.txt"
$LOG_FILE    = Join-Path $InstallDir "atualizar.log"
$TEMP_DIR    = Join-Path $env:TEMP "sigedash-update"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

function VeraoParaNumero($v) {
    # Converte "1.2.3" em [System.Version] para comparacao
    try { return [System.Version]$v } catch { return [System.Version]"0.0.0" }
}

Log "=== SigeDash - Verificacao de Atualizacao ==="

# Le versao instalada
$versaoAtual = "0.0.0"
if (Test-Path $VERSION_TXT) {
    $versaoAtual = (Get-Content $VERSION_TXT -Raw).Trim()
    Log "Versao instalada : $versaoAtual"
} else {
    Log "version.txt nao encontrado - assumindo 0.0.0"
}

# Consulta ultima release no GitHub
Log "Consultando GitHub Releases..."
$apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
try {
    $headers = @{ "User-Agent" = "SigeDash-Updater/1.0" }
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30
} catch {
    Log "AVISO: Nao foi possivel contatar o GitHub: $_"
    Log "Verifique a conexao com a internet. Nenhuma atualizacao aplicada."
    exit 0
}

$tagLatest = $release.tag_name.TrimStart("v")
Log "Versao disponivel: $tagLatest"

# Compara versoes
$verAtual  = VeraoParaNumero $versaoAtual
$verLatest = VeraoParaNumero $tagLatest

if (-not $Forcar -and $verLatest -le $verAtual) {
    Log "Sistema ja esta na versao mais recente. Nenhuma acao necessaria."
    exit 0
}

Log "Nova versao disponivel: $tagLatest (atual: $versaoAtual)"

# Localiza o asset ZIP na release
$asset = $release.assets | Where-Object { $_.name -like "SigeDash-Deploy-v*.zip" } | Select-Object -First 1
if (-not $asset) {
    Log "ERRO: Nao encontrei arquivo ZIP na release $tagLatest."
    exit 1
}

$downloadUrl = $asset.browser_download_url
$zipName     = $asset.name
$zipPath     = Join-Path $TEMP_DIR $zipName
$extractPath = Join-Path $TEMP_DIR "extracted"

Log "Baixando: $zipName ..."
New-Item -ItemType Directory -Path $TEMP_DIR    -Force | Out-Null
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($downloadUrl, $zipPath)
    Log "Download concluido."
} catch {
    Log "ERRO ao baixar: $_"
    exit 1
}

# Extrai o pacote
Log "Extraindo pacote..."
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Para os servicos (backend e agente) antes de sobrescrever binarios
foreach ($nome in @($SVC_NAME, $SVC_AGENTE)) {
    $s = Get-Service $nome -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq "Running") {
        Log "Parando servico $nome ..."
        Stop-Service $nome -Force
    }
}
Start-Sleep -Seconds 3

# 1) Backend: tudo, exceto a subpasta 'agente\' e o appsettings.Production.json (senhas do cliente)
$arqBackend = Get-ChildItem $extractPath -Recurse -File | Where-Object {
    $_.Name -ne "appsettings.Production.json" -and $_.FullName -notmatch '\\agente\\'
}
$qtdBack = 0
foreach ($f in $arqBackend) {
    $relativo = $f.FullName.Substring($extractPath.Length + 1)
    $destino  = Join-Path $InstallDir $relativo
    New-Item -ItemType Directory -Path (Split-Path $destino) -Force | Out-Null
    Copy-Item $f.FullName $destino -Force
    $qtdBack++
}
Log "Backend: $qtdBack arquivos atualizados (appsettings.Production.json preservado)."

# 2) Agente: binarios + SQL + indicadores.json, preservando Config\agente.config.json (config do cliente)
$agenteSrc = Join-Path $extractPath "agente"
if ((Test-Path $agenteSrc) -and (Test-Path $AgenteDir)) {
    $arqAgente = Get-ChildItem $agenteSrc -Recurse -File | Where-Object {
        $_.FullName -notmatch '\\Config\\agente\.config\.json$'
    }
    $qtdAg = 0
    foreach ($f in $arqAgente) {
        $relativo = $f.FullName.Substring($agenteSrc.Length + 1)
        $destino  = Join-Path $AgenteDir $relativo
        New-Item -ItemType Directory -Path (Split-Path $destino) -Force | Out-Null
        Copy-Item $f.FullName $destino -Force
        $qtdAg++
    }
    Log "Agente: $qtdAg arquivos atualizados (Config\agente.config.json preservado)."
} elseif (Test-Path $agenteSrc) {
    Log "Agente nao instalado em $AgenteDir - pulando atualizacao do agente."
} else {
    Log "Pacote sem subpasta 'agente' - atualizando apenas o backend."
}

# Reinicia os servicos
foreach ($nome in @($SVC_NAME, $SVC_AGENTE)) {
    $s = Get-Service $nome -ErrorAction SilentlyContinue
    if ($s) {
        Log "Iniciando servico $nome ..."
        Start-Service $nome -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 4

$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Log "Backend reiniciado com sucesso."
} else {
    Log "AVISO: $SVC_NAME nao voltou a Running. Verifique o Event Viewer."
}
$svcAg = Get-Service $SVC_AGENTE -ErrorAction SilentlyContinue
if ($svcAg) {
    if ($svcAg.Status -eq "Running") { Log "Agente reiniciado com sucesso." }
    else { Log "AVISO: $SVC_AGENTE nao voltou a Running (status: $($svcAg.Status))." }
}

# Limpa temporarios
try {
    Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

Log ""
Log "=== Atualizacao concluida: $versaoAtual -> $tagLatest ==="
