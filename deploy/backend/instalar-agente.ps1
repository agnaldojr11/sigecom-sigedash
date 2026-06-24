<#
.SYNOPSIS
    Instala o SigeDash Agente como Windows Service no servidor do cliente.
.DESCRIPTION
    - Copia os binarios do agente para C:\Program Files\SistemasBr\SigeDash
    - Registra o cliente no backend e grava Config\agente.config.json (via configurar-cliente.ps1)
    - Registra e inicia o Windows Service "SigeDashAgente"

    Substitui o antigo instalador InnoSetup (interativo). Totalmente nao-interativo.
.PARAMETER BackendUrl
    URL do backend local. Padrao: http://localhost:5000
.PARAMETER AdminKey
    Chave de administracao do backend (gerada pelo instalar-backend.ps1).
.PARAMETER ClienteNome
    Nome da empresa/cliente.
.PARAMETER FdbPath
    Caminho do arquivo .FDB do Sigecom.
.PARAMETER AgenteSrc
    Pasta com os binarios do agente. Padrao: subpasta 'agente' onde este script esta.
.PARAMETER InstallDir
    Pasta de instalacao do agente. Padrao: C:\Program Files\SistemasBr\SigeDash
.EXAMPLE
    .\instalar-agente.ps1 -AdminKey "chave" -ClienteNome "Amaral" -FdbPath "C:\SIGECOM\SIGECOM.FDB"
#>
param(
    [Parameter(Mandatory)]
    [string]$AdminKey,
    [Parameter(Mandatory)]
    [string]$ClienteNome,
    [Parameter(Mandatory)]
    [string]$FdbPath,

    [string]$BackendUrl = "http://localhost:5000",
    [string]$AgenteSrc  = (Join-Path $PSScriptRoot "agente"),
    [string]$InstallDir = "C:\Program Files\SistemasBr\SigeDash"
)

$ErrorActionPreference = "Stop"
$SVC_NAME = "SigeDashAgente"
$SVC_EXE  = Join-Path $InstallDir "SigeDash.Agente.exe"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
}

# --- Verifica privilegio de admin ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

Log "=== SigeDash Agente - Instalacao ==="
Log "Origem  : $AgenteSrc"
Log "Destino : $InstallDir"
Log "Cliente : $ClienteNome"

# --- Valida origem dos binarios ---
if (-not (Test-Path (Join-Path $AgenteSrc "SigeDash.Agente.exe"))) {
    Log "ERRO: binarios do agente nao encontrados em $AgenteSrc"
    Log "(SigeDash.Agente.exe ausente). Verifique o pacote de deploy."
    exit 1
}

# --- Para e remove servico existente ---
$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if ($svc) {
    Log "Servico $SVC_NAME ja existe - parando e removendo..."
    Stop-Service $SVC_NAME -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    & sc.exe delete $SVC_NAME | Out-Null
    Start-Sleep -Seconds 1
}

# --- Copia binarios ---
Log "Copiando binarios..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item "$AgenteSrc\*" $InstallDir -Recurse -Force
Log "Binarios copiados."

# --- Registra cliente no backend e grava config no lugar certo ({InstallDir}\Config) ---
# O agente le o config de {exe}\Config\agente.config.json - por isso ConfigDir aponta para la.
$scriptConf = Join-Path $PSScriptRoot "configurar-cliente.ps1"
if (-not (Test-Path $scriptConf)) {
    $scriptConf = Join-Path $InstallDir "configurar-cliente.ps1"
}
if (-not (Test-Path $scriptConf)) {
    Log "ERRO: configurar-cliente.ps1 nao encontrado."
    exit 1
}

Log "Registrando cliente no backend e gravando config..."
& $scriptConf `
    -BackendUrl  $BackendUrl `
    -AdminKey    $AdminKey `
    -ClienteNome $ClienteNome `
    -FdbPath     $FdbPath `
    -ConfigDir   (Join-Path $InstallDir "Config")
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Log "ERRO: configurar-cliente.ps1 falhou com codigo $LASTEXITCODE"
    exit 1
}
Log "Cliente configurado."

# --- Registra o Windows Service ---
Log "Registrando servico $SVC_NAME ..."
& sc.exe create $SVC_NAME binPath= "`"$SVC_EXE`"" start= auto DisplayName= "SigeDash Agente" | Out-Null
& sc.exe description $SVC_NAME "Coleta indicadores do SIGECOM (Firebird, somente leitura) e envia ao backend SigeDash." | Out-Null
Log "Servico registrado."

# --- Inicia o servico ---
Log "Iniciando servico..."
try {
    Start-Service $SVC_NAME
} catch {
    Log "ERRO ao iniciar servico: $_"
    Log "Verifique o Event Viewer -> Logs do Windows -> Aplicativo"
    exit 1
}
Start-Sleep -Seconds 4

$svc = Get-Service $SVC_NAME
Log "Status: $($svc.Status)"
if ($svc.Status -eq "Running") {
    Log "=== Agente instalado e rodando! ==="
    Log "Sincronizacao de usuarios e indicadores comeca nos proximos minutos."
} else {
    Log "AVISO: servico nao esta em Running (status: $($svc.Status)). Verifique o Event Viewer."
    exit 1
}
