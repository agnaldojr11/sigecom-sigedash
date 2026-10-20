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
    [string]$Repo       = "agnaldojr11/sigecom-sigedash",
    [switch]$Forcar,
    # Emergencia: permite aplicar pacote NAO assinado (por padrao exige assinatura EV da SistemasBr).
    [switch]$PermitirNaoAssinado
)

# Assinante EV esperado no pacote (defesa contra pacote adulterado - auditoria A-03).
$SIGNER_ESPERADO = "SISTEMASBR"

$ErrorActionPreference = "Stop"

# Windows Server antigo (2012R2/2016) usa TLS 1.0/1.1 por padrao no .NET, e o GitHub exige TLS 1.2+.
# Sem isto a consulta/download da release falha com "Could not create SSL/TLS secure channel".
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13 } catch {}

$SVC_NAME   = "SigeDashBackend"
$SVC_AGENTE = "SigeDashAgente"
$VERSION_TXT = Join-Path $InstallDir "version.txt"
$LOG_FILE    = Join-Path $InstallDir "atualizar.log"
# Pasta temporaria SEGURA (sem nome de usuario - perfis com acento quebravam caminhos).
$TEMP_DIR    = Join-Path $(if (Test-Path "C:\Windows\Temp") { "C:\Windows\Temp" } else { $env:TEMP }) "sigedash-update"
# Trava de manutencao: enquanto existir (e for recente), o watchdog NAO mexe nos servicos.
$LOCK_FILE   = "C:\SigeDash\manutencao.lock"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content -LiteralPath $LOG_FILE -Value $line -Encoding UTF8 } catch {}
}

# Self-heal das tarefas agendadas. Roda SEMPRE (inclusive quando nao ha versao nova), para que
# clientes que so ATUALIZAM ganhem: a atualizacao in-app (SigeDash-Aplicar) e o watchdog (502).
function GarantirTarefas() {
    try {
        $TASK_APLICAR = "SigeDash-Aplicar"
        if (-not (Get-ScheduledTask -TaskName $TASK_APLICAR -ErrorAction SilentlyContinue)) {
            $selfPath = Join-Path $InstallDir "atualizar.ps1"
            $act = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$selfPath`""
            $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -StartWhenAvailable
            Register-ScheduledTask -TaskName $TASK_APLICAR -Action $act -Settings $set `
                -RunLevel Highest -User "SYSTEM" `
                -Description "Aplica a atualizacao do SigeDash sob demanda (disparada pelo painel)" | Out-Null
            Log "Tarefa sob demanda $TASK_APLICAR criada (self-heal)."
        }
    } catch { Log "AVISO: nao foi possivel garantir a tarefa SigeDash-Aplicar: $_" }
    try {
        $wdInst = Join-Path $InstallDir "instalar-watchdog.ps1"
        if ((Test-Path -LiteralPath $wdInst) -and -not (Get-ScheduledTask -TaskName "SigeDash-Watchdog" -ErrorAction SilentlyContinue)) {
            & powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File $wdInst -InstallDir $InstallDir | Out-Null
            Log "Watchdog registrado (self-heal)."
        }
    } catch { Log "AVISO: nao foi possivel registrar o watchdog: $_" }
}

function VeraoParaNumero($v) {
    # Converte "1.2.3" em [System.Version] para comparacao
    try { return [System.Version]$v } catch { return [System.Version]"0.0.0" }
}

Log "=== SigeDash - Verificacao de Atualizacao ==="
GarantirTarefas

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
# Limpa sobra de uma atualizacao anterior que falhou (a extracao .NET falha se ja houver arquivos).
if (Test-Path -LiteralPath $TEMP_DIR) { try { [System.IO.Directory]::Delete($TEMP_DIR, $true) } catch {} }
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

# Extrai o pacote. Expand-Archive so existe no PowerShell 5+; o Windows Server 2012/2012R2 vem com
# PowerShell 3/4 -> sem este fallback o auto-update NUNCA funcionava nesses servidores.
Log "Extraindo pacote..."
try {
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
    }
} catch {
    Log "ERRO ao extrair o pacote: $_"
    exit 1
}

# Verifica a assinatura Authenticode dos executaveis ANTES de aplicar (auditoria A-03).
# Comprometer o repo/release nao basta: pacote sem assinatura EV valida da SistemasBr e recusado.
$exesVerificar = @(
    (Join-Path $extractPath "SigeDash.Api.exe"),
    (Join-Path $extractPath "agente\SigeDash.Agente.exe")
) | Where-Object { Test-Path $_ }

if ($exesVerificar.Count -eq 0) {
    Log "ERRO: nenhum executavel encontrado no pacote para verificar - abortando."
    exit 1
}
foreach ($exe in $exesVerificar) {
    $sig = Get-AuthenticodeSignature $exe
    $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "" }
    $nome = Split-Path $exe -Leaf
    if ($sig.Status -eq 'Valid' -and $subject -match $SIGNER_ESPERADO) {
        Log "Assinatura OK: $nome ($(($subject -split ',')[0]))"
    }
    elseif ($sig.Status -eq 'Valid') {
        Log "ERRO: $nome assinado por OUTRO emissor ($subject) - abortando (pacote suspeito)."
        exit 1
    }
    elseif ($PermitirNaoAssinado) {
        Log "AVISO: $nome sem assinatura valida ($($sig.Status)) - prosseguindo por -PermitirNaoAssinado."
    }
    else {
        Log "ERRO: $nome sem assinatura EV valida da SistemasBr ($($sig.Status)) - abortando."
        Log "Assine o pacote antes de publicar (ou use -PermitirNaoAssinado apenas para pacote de teste)."
        exit 1
    }
}

# Trava de manutencao: impede o watchdog (a cada 5 min) de religar o backend no meio da copia
# (arquivo travado = atualizacao parcial). Expira sozinha em 2h se algo der muito errado.
try { New-Item -ItemType Directory -Path (Split-Path $LOCK_FILE) -Force | Out-Null
      Set-Content -LiteralPath $LOCK_FILE -Value "atualizar $(Get-Date -Format s)" -Encoding ASCII } catch {}

$falhaAplicar = $null
try {   # finally abaixo: os servicos SEMPRE voltam, mesmo se a copia falhar no meio

# Para os servicos (backend e agente) antes de sobrescrever binarios
foreach ($nome in @($SVC_NAME, $SVC_AGENTE)) {
    $s = Get-Service $nome -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq "Running") {
        Log "Parando servico $nome ..."
        Stop-Service $nome -Force -ErrorAction SilentlyContinue
    }
}
# Processo que nao encerrou segura os .exe/.dll e faz a copia falhar.
foreach ($p in @("SigeDash.Api", "SigeDash.Agente")) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

# 1) Backend: tudo, exceto a subpasta 'agente\' e o appsettings.Production.json (senhas do cliente)
$arqBackend = Get-ChildItem $extractPath -Recurse -File | Where-Object {
    $_.Name -ne "appsettings.Production.json" -and $_.FullName -notmatch '\\agente\\' `
    -and $_.Name -ne "Instalar-SigeDash.exe"   # instalador (68 MB) so serve p/ install novo, nao p/ update
}
$qtdBack = 0
foreach ($f in $arqBackend) {
    $relativo = $f.FullName.Substring($extractPath.Length + 1)
    $destino  = Join-Path $InstallDir $relativo
    New-Item -ItemType Directory -Path (Split-Path $destino) -Force | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $destino -Force
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
        Copy-Item -LiteralPath $f.FullName -Destination $destino -Force
        $qtdAg++
    }
    Log "Agente: $qtdAg arquivos atualizados (Config\agente.config.json preservado)."
} elseif (Test-Path $agenteSrc) {
    Log "Agente nao instalado em $AgenteDir - pulando atualizacao do agente."
} else {
    Log "Pacote sem subpasta 'agente' - atualizando apenas o backend."
}

} catch {
    $falhaAplicar = $_
    Log "ERRO durante a copia da atualizacao: $_"
} finally {
    # Reinicia os servicos SEMPRE (mesmo com falha) - nunca deixa o cliente fora do ar.
    foreach ($nome in @($SVC_NAME, $SVC_AGENTE)) {
        $s = Get-Service $nome -ErrorAction SilentlyContinue
        if ($s) {
            Log "Iniciando servico $nome ..."
            Start-Service $nome -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 4
    try { Remove-Item -LiteralPath $LOCK_FILE -Force -ErrorAction SilentlyContinue } catch {}
}

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

# Limpa temporarios (caminho literal: sem expansao de curinga)
try { [System.IO.Directory]::Delete($TEMP_DIR, $true) } catch {}

if ($falhaAplicar) {
    Log "=== Atualizacao NAO concluida (servicos religados na versao anterior/parcial). Rode de novo. ==="
    exit 1
}

# Self-heal de novo: os arquivos novos (ex.: instalar-watchdog.ps1) acabaram de chegar.
GarantirTarefas

Log ""
Log "=== Atualizacao concluida: $versaoAtual -> $tagLatest ==="
