<#
.SYNOPSIS
    Configura autenticacao GitHub via Windows Credential Manager e faz o push inicial.
.DESCRIPTION
    - Armazena o Personal Access Token no Windows Credential Manager (criptografado pelo SO)
    - O Git usa automaticamente a credencial em todos os pushes futuros
    - Nenhuma senha fica em arquivo de texto no disco
.PARAMETER Repo
    URL HTTPS do repositorio. Padrao: https://github.com/agnaldojr11/sigecom-sigedash.git
.PARAMETER Branch
    Branch a enviar. Padrao: main
.EXAMPLE
    .\configurar-github.ps1
    .\configurar-github.ps1 -Repo "https://github.com/agnaldojr11/sigecom-sigedash.git"
#>
param(
    [string]$Repo   = "https://github.com/agnaldojr11/sigecom-sigedash.git",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

function Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
}

function Titulo($msg) {
    Write-Host ""
    Write-Host $msg -ForegroundColor Cyan
    Write-Host ("-" * ([Math]::Min($msg.Length + 4, 60))) -ForegroundColor DarkGray
}

# ── Verifica git instalado ────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log "ERRO: git nao encontrado. Instale em https://git-scm.com" Red
    exit 1
}

$gitVersion = git --version
Log "Git encontrado: $gitVersion" DarkGray

# ── Verifica se e um repositorio git ─────────────────────────────────────────
$repoDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $repoDir ".git"))) {
    Log "ERRO: Este diretorio nao e um repositorio git: $repoDir" Red
    exit 1
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  SigeDash - Configuracao do GitHub" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Log "Repositorio : $Repo"
Log "Branch      : $Branch"
Log ""
Log "O token sera armazenado no Windows Credential Manager." DarkGray
Log "Ele fica criptografado pelo Windows  -  nao e salvo em disco." DarkGray

# ── Solicita o Personal Access Token ─────────────────────────────────────────
Titulo "[1] Informe o Personal Access Token do GitHub"
Log "Acesse: GitHub -> Settings -> Developer settings -> Personal access tokens"
Log "Permissoes necessarias: repo (Full control)"
Log ""

$tokenSeguro = Read-Host "Cole o token aqui (nao sera exibido)" -AsSecureString
$tokenPlain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSeguro))

if ([string]::IsNullOrWhiteSpace($tokenPlain)) {
    Log "ERRO: token nao informado." Red
    exit 1
}

# Extrai usuario/host da URL do repo para salvar a credencial corretamente
# Formato: https://github.com/dono/repo.git
$uri      = [System.Uri]$Repo
$host_url = "$($uri.Scheme)://$($uri.Host)"

# ── Armazena no Windows Credential Manager via git credential approve ─────────
Titulo "[2] Salvando credencial no Windows Credential Manager..."

# Extrai o usuario do token via API do GitHub
try {
    $headers   = @{ Authorization = "Bearer $tokenPlain"; "User-Agent" = "SigeDash-Setup" }
    $ghUser    = Invoke-RestMethod "https://api.github.com/user" -Headers $headers -TimeoutSec 15
    $ghLogin   = $ghUser.login
    Log "Autenticado como: $ghLogin" Green
} catch {
    Log "AVISO: nao foi possivel verificar o usuario via API: $_" Yellow
    $ghLogin = "git"
}

# Injeta credencial no Git Credential Manager
$credInput = "protocol=$($uri.Scheme)`nhost=$($uri.Host)`nusername=$ghLogin`npassword=$tokenPlain`n"
$credInput | git credential approve
if ($LASTEXITCODE -ne 0) {
    Log "AVISO: git credential approve retornou erro $LASTEXITCODE" Yellow
} else {
    Log "Credencial armazenada no Windows Credential Manager." Green
}

# Limpa o token da memoria
$tokenPlain = $null
[GC]::Collect()

# ── Configura o remote ────────────────────────────────────────────────────────
Titulo "[3] Configurando remote 'origin'..."

$remoteAtual = git -C $repoDir remote get-url origin 2>$null
if ($remoteAtual) {
    git -C $repoDir remote set-url origin $Repo
    Log "Remote atualizado: $Repo" Green
} else {
    git -C $repoDir remote add origin $Repo
    Log "Remote adicionado: $Repo" Green
}

# ── Testa a conexao ───────────────────────────────────────────────────────────
Titulo "[4] Testando conexao com o GitHub..."

git -C $repoDir ls-remote --heads origin 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Log "ERRO: nao foi possivel conectar ao repositorio." Red
    Log "Verifique se o token tem permissao 'repo' e se a URL esta correta." Yellow
    exit 1
}
Log "Conexao OK." Green

# ── Push inicial ──────────────────────────────────────────────────────────────
Titulo "[5] Enviando codigo para o GitHub..."

# Verifica se o branch remoto existe
$remoteBranch = git -C $repoDir ls-remote --heads origin $Branch 2>$null
if ($remoteBranch) {
    Log "Branch '$Branch' ja existe no remoto. Enviando commits novos..."
    git -C $repoDir push origin $Branch
} else {
    Log "Primeiro push do branch '$Branch'..."
    git -C $repoDir push -u origin $Branch
}

if ($LASTEXITCODE -ne 0) {
    Log "ERRO no push. Verifique conflitos ou permissoes." Red
    exit 1
}
Log "Branch '$Branch' enviado." Green

# Envia tags existentes
$tags = git -C $repoDir tag
if ($tags) {
    Log "Enviando tags: $($tags -join ', ')..."
    git -C $repoDir push origin --tags
    Log "Tags enviadas." Green
} else {
    Log "Sem tags locais para enviar."
}

# ── Resumo ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Configuracao concluida!" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Log "Repositorio : $Repo"
Log "Usuario     : $ghLogin"
Log "Branch      : $Branch"
Write-Host ""
Log "Proximos passos:" Yellow
Log "  - Para publicar uma release: git tag v1.0.0 && git push origin v1.0.0"
Log "  - O GitHub Actions vai compilar e publicar o ZIP automaticamente."
Log "  - Acompanhe em: $($Repo.Replace('.git',''))/actions"
Write-Host ""
