<#
.SYNOPSIS
    Instala o SigeDash Backend como Windows Service no servidor do cliente.
.DESCRIPTION
    - Copia os arquivos publicados para C:\SigeDash\Backend\
    - Gera appsettings.Production.json com senhas informadas
    - Registra e inicia o Windows Service "SigeDashBackend"
.PARAMETER PostgresSenha
    Senha do usuario 'sigedash' no PostgreSQL local.
.PARAMETER AdminKey
    Chave de administracao para criar/listar clientes no backend.
    Se omitida, sera gerada automaticamente.
.PARAMETER PublishDir
    Pasta com os arquivos do dotnet publish. Padrao: pasta onde este script esta.
.PARAMETER InstallDir
    Pasta de instalacao no servidor. Padrao: C:\SigeDash\Backend
.EXAMPLE
    .\instalar-backend.ps1 -PostgresSenha "minhasenha123" -AdminKey "chaveforte"
#>
param(
    [Parameter(Mandatory)]
    [string]$PostgresSenha,

    [string]$AdminKey   = "",
    [string]$PublishDir = $PSScriptRoot,
    [string]$InstallDir = "C:\SigeDash\Backend"
)

$ErrorActionPreference = "Stop"
$SVC_NAME = "SigeDashBackend"
$SVC_EXE  = Join-Path $InstallDir "SigeDash.Api.exe"
$LOG_FILE = Join-Path $InstallDir "install.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

# --- Verifica privilegio de admin ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

Log "=== SigeDash Backend - Instalacao ==="
Log "PublishDir : $PublishDir"
Log "InstallDir : $InstallDir"

# --- Para e remove servico existente ---
$svc = Get-Service $SVC_NAME -ErrorAction SilentlyContinue
if ($svc) {
    Log "Servico $SVC_NAME encontrado - parando..."
    Stop-Service $SVC_NAME -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    sc.exe delete $SVC_NAME | Out-Null
    Log "Servico removido."
}

# --- Copia arquivos do publish ---
Log "Copiando arquivos para $InstallDir ..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item "$PublishDir\*" $InstallDir -Recurse -Force
Log "Arquivos copiados."

# --- Gera chaves se nao fornecidas (CSPRNG; NUNCA Get-Random para segredos) ---
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    $b = New-Object byte[] 32; $rng.GetBytes($b)
    $AdminKey = [Convert]::ToBase64String($b)
    Log "AdminKey gerada automaticamente."
}

# JWT key: 48 bytes (384 bits) de CSPRNG
$jb = New-Object byte[] 48; $rng.GetBytes($jb)
$JwtKey = [Convert]::ToBase64String($jb)

# --- Grava appsettings.Production.json ---
$config = @{
    Urls = "http://localhost:5000"
    ConnectionStrings = @{
        Postgres = "Host=localhost;Port=5432;Database=sigedash;Username=sigedash;Password=$PostgresSenha"
    }
    Jwt = @{
        Issuer    = "sigedash"
        Audience  = "sigedash-pwa"
        SecretKey = $JwtKey
    }
    AdminKey       = $AdminKey
    AllowedOrigins = @()
    Logging = @{
        LogLevel = @{
            Default                   = "Information"
            "Microsoft.AspNetCore"    = "Warning"
        }
    }
}

$configPath = Join-Path $InstallDir "appsettings.Production.json"
$config | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
Log "appsettings.Production.json gerado."

# --- Verifica acesso ao banco antes de registrar o servico ---
$psqlCmd = Get-Command psql.exe -ErrorAction SilentlyContinue
if (-not $psqlCmd) {
    foreach ($v in @("17","16","15","14","13")) {
        $c = "C:\Program Files\PostgreSQL\$v\bin\psql.exe"
        if (Test-Path $c) { $psqlCmd = @{ Source = $c }; break }
    }
}
if ($psqlCmd) {
    $env:PGPASSWORD = $PostgresSenha
    # -t -A: saida sem cabecalho nem contagem de linhas (funciona em qualquer idioma do PostgreSQL)
    $dbTest = & $psqlCmd.Source -U sigedash -d sigedash -h localhost -t -A -c "SELECT 1" 2>&1
    $env:PGPASSWORD = $null
    if (($dbTest | Out-String).Trim() -match "^1") {
        Log "Conexao com banco 'sigedash' verificada com sucesso."
    } else {
        Log "ERRO: nao foi possivel conectar ao banco 'sigedash'. Verifique se o PostgreSQL esta rodando e o banco existe."
        Log "Detalhe: $($dbTest | Out-String)"
        exit 1
    }
} else {
    Log "AVISO: psql.exe nao encontrado - pulando verificacao do banco."
}

# --- Registra o Windows Service ---
Log "Registrando servico $SVC_NAME ..."
$binPath = "`"$SVC_EXE`""
sc.exe create $SVC_NAME binPath= $binPath start= auto obj= LocalSystem | Out-Null
sc.exe description $SVC_NAME "SigeDash Backend API + PWA (SistemasBr)" | Out-Null

# Configura variavel de ambiente ASPNETCORE_ENVIRONMENT=Production para o servico
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$SVC_NAME"
New-ItemProperty -Path $regPath -Name "Environment" -PropertyType MultiString `
    -Value @("ASPNETCORE_ENVIRONMENT=Production") -Force | Out-Null

Log "Servico registrado."

# --- Inicia o servico ---
Log "Iniciando $SVC_NAME ..."
try {
    Start-Service $SVC_NAME
} catch {
    # Captura o erro real do Event Log para diagnose mais clara
    $evtErro = Get-EventLog -LogName Application -Source ".NET Runtime","Application Error" `
        -Newest 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "SigeDash" } |
        Select-Object -First 1
    if ($evtErro) {
        Log "ERRO: servico nao iniciou. Detalhe do Event Log: $($evtErro.Message)"
    } else {
        Log "ERRO ao iniciar servico: $_"
    }
    Log "Verifique: Event Viewer -> Logs de Aplicativos e Servicos"
    exit 1
}
Start-Sleep -Seconds 4

$svc = Get-Service $SVC_NAME
if ($svc.Status -eq "Running") {
    Log "Servico iniciado com sucesso."
} else {
    Log "AVISO: servico nao esta em Running (status: $($svc.Status)). Verifique o Event Viewer."
}

# --- Testa o endpoint ---
Start-Sleep -Seconds 3
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:5000/auth/empresas" -UseBasicParsing -TimeoutSec 10
    Log "Backend respondendo na porta 5000. Status: $($resp.StatusCode)"
} catch {
    Log "AVISO: backend ainda nao respondeu na porta 5000. Aguarde alguns segundos e tente novamente."
}

# --- Agendador de atualizacoes automaticas ---
$TASK_NAME    = "SigeDash-Atualizar"
$atualizarSrc = Join-Path $PublishDir "atualizar.ps1"
$atualizarDst = Join-Path $InstallDir "atualizar.ps1"

if (Test-Path $atualizarSrc) {
    Copy-Item $atualizarSrc $atualizarDst -Force

    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue

    $action  = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$atualizarDst`""

    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "03:00"

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable

    Register-ScheduledTask `
        -TaskName    $TASK_NAME `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -RunLevel    Highest `
        -User        "SYSTEM" `
        -Description "Verifica e aplica atualizacoes automaticas do SigeDash" | Out-Null

    Log "Tarefa agendada: $TASK_NAME (toda segunda as 03:00)"
} else {
    Log "AVISO: atualizar.ps1 nao encontrado - agendamento ignorado."
}

# --- Resumo ---
Log ""
Log "=== Instalacao concluida! ==="
Log "Servico  : $SVC_NAME"
Log "Diretorio: $InstallDir"
# AdminKey vai SO para o console (nao para o arquivo de log) - segredo
Write-Host "AdminKey : $AdminKey" -ForegroundColor Yellow
Log "URL local: http://localhost:5000"
Log ""
Log "IMPORTANTE: anote a AdminKey exibida acima (nao fica salva em log) - ela e necessaria para criar usuarios."
Log "Proximo passo: executar configurar-cliente.ps1 com esta AdminKey."
