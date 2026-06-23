<#
.SYNOPSIS
    Instala o PostgreSQL 16 e prepara o banco de dados para o SigeDash.
.DESCRIPTION
    - Verifica se o PostgreSQL ja esta instalado (TCP porta 5432, servico Windows, psql no PATH)
    - Quando ja instalado: descobre a senha do postgres e cria usuario/banco sigedash
    - Quando nao instalado: baixa e instala PostgreSQL 16 via EDB (modo silencioso)
.PARAMETER SigeDashSenha
    Senha do usuario 'sigedash' no banco (usada pelo backend).
.PARAMETER SuperSenha
    Senha do superusuario 'postgres'. Gerada automaticamente em nova instalacao.
.PARAMETER InstallerExe
    Caminho para o installer EDB ja baixado. Se omitido, faz o download.
.EXAMPLE
    .\instalar-postgres.ps1 -SigeDashSenha "senhasegura123"
#>
param(
    [Parameter(Mandatory)]
    [string]$SigeDashSenha,

    [string]$SuperSenha   = "",
    [string]$InstallerExe = ""
)

$ErrorActionPreference = "Stop"

$PG_VERSION    = "16"
$PG_INSTALLDIR = "C:\Program Files\PostgreSQL\$PG_VERSION"
$PG_BIN        = "$PG_INSTALLDIR\bin"
$PG_SVC        = "postgresql-x64-$PG_VERSION"
$LOG_FILE      = "$env:TEMP\sigedash-postgres-install.log"

function Log($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}

# Retorna $true se conseguir abrir TCP na porta
function TestaTCP($porta) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient("localhost", $porta)
        $tcp.Close()
        return $true
    } catch { return $false }
}

# Descobre o psql.exe disponivel (v16, qualquer versao ou PATH)
function DescobriPsql() {
    # Versao configurada como alvo
    if (Test-Path "$PG_INSTALLDIR\bin\psql.exe") {
        return "$PG_INSTALLDIR\bin\psql.exe"
    }
    # Qualquer versao instalada
    foreach ($v in @("17","16","15","14","13")) {
        $c = "C:\Program Files\PostgreSQL\$v\bin\psql.exe"
        if (Test-Path $c) { return $c }
    }
    # PATH do sistema
    $cmd = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Verifica privilegio de admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

Log "=== SigeDash - Instalacao do PostgreSQL $PG_VERSION ==="

# --- Detecta PostgreSQL existente ---
# Prioridade: TCP porta 5432 (mais confiavel), depois servico Windows, depois exe
$portaEmUso  = TestaTCP 5432
$pgSvcAtual  = Get-Service | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
$psqlExe     = DescobriPsql

$jaInstalado = $portaEmUso -or ($null -ne $pgSvcAtual) -or ($null -ne $psqlExe)

if ($jaInstalado) {
    if ($portaEmUso) {
        Log "PostgreSQL ja esta rodando na porta 5432 - pulando instalacao."
    } elseif ($pgSvcAtual) {
        Log "Servico PostgreSQL encontrado: $($pgSvcAtual.Name) - pulando instalacao."
    } else {
        Log "psql.exe encontrado em: $psqlExe - pulando instalacao."
    }

    # Garante psql.exe disponivel
    if (-not $psqlExe) {
        Log "ERRO: PostgreSQL detectado (porta 5432 ativa) mas psql.exe nao encontrado."
        Log "Verifique se o PostgreSQL esta instalado corretamente e psql.exe esta no PATH."
        exit 1
    }
    $PG_BIN = Split-Path $psqlExe

    # Descobre a senha do superusuario postgres existente
    # Tenta trust auth primeiro (sem senha) - comum em instalacoes locais
    $env:PGPASSWORD = ""
    $testOut = & $psqlExe -U postgres -d postgres -c "SELECT 1" 2>&1
    $env:PGPASSWORD = $null

    if ($testOut -match "1 row") {
        $SuperSenha = ""
        Log "PostgreSQL aceita conexao local sem senha (trust). Continuando."
    } else {
        Write-Host ""
        Write-Host "PostgreSQL ja esta instalado nesta maquina." -ForegroundColor Yellow
        Write-Host "Informe a senha do usuario 'postgres' para criar o banco do SigeDash." -ForegroundColor Yellow
        Write-Host "(A senha foi definida quando o PostgreSQL foi instalado nesta maquina)" -ForegroundColor DarkYellow
        Write-Host ""
        $pgSenhaSegura = Read-Host -AsSecureString "Senha do postgres"
        $SuperSenha    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pgSenhaSegura))

        $env:PGPASSWORD = $SuperSenha
        $testOut2 = & $psqlExe -U postgres -d postgres -c "SELECT 1" 2>&1
        $env:PGPASSWORD = $null

        if ($testOut2 -notmatch "1 row") {
            Log "ERRO: senha invalida ou acesso recusado: $testOut2"
            exit 1
        }
        Log "Conexao com postgres OK usando senha informada."
    }
} else {
    # Nova instalacao
    if ([string]::IsNullOrWhiteSpace($SuperSenha)) {
        $bytes      = 1..18 | ForEach-Object { [byte](Get-Random -Max 256) }
        $SuperSenha = [Convert]::ToBase64String($bytes)
        Log "SuperSenha do postgres gerada automaticamente."
    }

    # Baixa o installer se necessario
    if ([string]::IsNullOrWhiteSpace($InstallerExe) -or -not (Test-Path $InstallerExe)) {
        $downloadUrl  = "https://get.enterprisedb.com/postgresql/postgresql-16.9-1-windows-x64.exe"
        $InstallerExe = "$env:TEMP\postgresql-16-windows-x64.exe"

        Log "Baixando PostgreSQL $PG_VERSION..."
        Log "(Isso pode levar alguns minutos)"

        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($downloadUrl, $InstallerExe)
            Log "Download concluido: $InstallerExe"
        } catch {
            Log "ERRO ao baixar: $_"
            Log "Baixe manualmente em: https://www.enterprisedb.com/downloads/postgres-postgresql-downloads"
            Log "Escolha: PostgreSQL $PG_VERSION -> Windows x86-64"
            Log "Depois execute: .\instalar-postgres.ps1 -SigeDashSenha '...' -InstallerExe 'C:\caminho\installer.exe'"
            exit 1
        }
    } else {
        Log "Usando installer: $InstallerExe"
    }

    # Executa instalacao silenciosa
    # Aspas no datadir evitam quebra de argumento em "C:\Program Files\..."
    Log "Instalando PostgreSQL $PG_VERSION (modo silencioso)..."
    $installerArgs = "--mode unattended " +
        "--superpassword `"$SuperSenha`" " +
        "--servicename $PG_SVC " +
        "--servicepassword `"$SuperSenha`" " +
        "--serverport 5432 " +
        "--datadir `"$PG_INSTALLDIR\data`" " +
        "--install_runtimes 0"

    $proc = Start-Process -FilePath $InstallerExe -ArgumentList $installerArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Log "ERRO: instalador retornou codigo $($proc.ExitCode)."
        Log "Verifique os logs em %TEMP%\postgresql_installer_*.log"
        exit 1
    }
    Log "PostgreSQL instalado com sucesso."

    $psqlExe = "$PG_INSTALLDIR\bin\psql.exe"
    $PG_BIN  = "$PG_INSTALLDIR\bin"
}

# --- Garante que o servico esta rodando ---
# Usa o servico real encontrado (nao necessariamente o v16)
$svcAtual = if ($pgSvcAtual) { $pgSvcAtual } else { Get-Service $PG_SVC -ErrorAction SilentlyContinue }

if (-not $svcAtual) {
    # Tenta de novo apos instalacao
    $svcAtual = Get-Service | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
}

if ($svcAtual) {
    if ($svcAtual.Status -ne "Running") {
        Log "Iniciando servico $($svcAtual.Name) ..."
        Start-Service $svcAtual.Name
        Start-Sleep -Seconds 3
    }
    Log "Servico $($svcAtual.Name) rodando."
    Set-Service $svcAtual.Name -StartupType Automatic | Out-Null
} else {
    if (-not (TestaTCP 5432)) {
        Log "AVISO: servico PostgreSQL nao encontrado. Verifique a instalacao manualmente."
    } else {
        Log "PostgreSQL respondendo na porta 5432 (servico nao identificado via Windows SCM)."
    }
}

# --- Cria usuario e banco sigedash ---
function Psql($sql, $db = "postgres") {
    $env:PGPASSWORD = $SuperSenha
    $out = & $psqlExe -U postgres -d $db -c $sql 2>&1
    $env:PGPASSWORD = $null
    return $out
}

Log "Criando usuario 'sigedash' no PostgreSQL..."
Psql "CREATE USER sigedash WITH PASSWORD '$SigeDashSenha'" | Out-Null
$out = Psql "ALTER USER sigedash WITH PASSWORD '$SigeDashSenha'"
Log "Usuario: $out"

$dbExiste = Psql "SELECT 1 FROM pg_database WHERE datname='sigedash'"
if ($dbExiste -notmatch "1 row") {
    $out = Psql "CREATE DATABASE sigedash OWNER sigedash ENCODING 'UTF8'"
    Log "Banco criado: $out"
} else {
    Log "Banco 'sigedash' ja existe."
}

$out = Psql "GRANT ALL PRIVILEGES ON DATABASE sigedash TO sigedash"
Log "Permissoes: $out"

# Testa conexao com o usuario sigedash
Log "Testando conexao com usuario 'sigedash'..."
$env:PGPASSWORD = $SigeDashSenha
$teste = & $psqlExe -U sigedash -d sigedash -c "SELECT version()" 2>&1
$env:PGPASSWORD = $null

if ($teste -match "PostgreSQL") {
    Log "Conexao OK - PostgreSQL respondendo para o usuario 'sigedash'."
} else {
    Log "ERRO: nao foi possivel conectar como usuario 'sigedash': $teste"
    Log "O banco pode estar com configuracao pg_hba.conf impedindo conexao local."
    exit 1
}

Log ""
Log "=== PostgreSQL pronto! ==="
Log "Banco   : sigedash"
Log "Usuario : sigedash"
Log "Senha   : $SigeDashSenha"
Log "Porta   : 5432"
Log ""
Log "Proximo passo: execute instalar-backend.ps1 -PostgresSenha '$SigeDashSenha'"
