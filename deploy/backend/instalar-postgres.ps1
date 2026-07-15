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
$freshInstall = -not $jaInstalado   # so aplicamos hardening no PG que NOS instalamos

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

    # Descobre a senha do superusuario postgres existente
    # -t -A: saida sem cabecalho nem contagem de linhas (evita variacao de idioma "1 row" vs "1 linha")
    $env:PGPASSWORD = ""
    $testOut = & $psqlExe -U postgres -d postgres -t -A -c "SELECT 1" 2>&1
    $env:PGPASSWORD = $null

    if (($testOut | Out-String).Trim() -match "^1") {
        $SuperSenha = ""
        Write-Host ""
        Write-Host "AVISO DE SEGURANCA: o PostgreSQL local aceita conexao SEM SENHA (modo 'trust')." -ForegroundColor Red
        Write-Host "Qualquer processo local pode conectar como superusuario. Recomendado apos a instalacao:" -ForegroundColor Yellow
        Write-Host "  - editar pg_hba.conf para 'scram-sha-256' nas conexoes locais e reiniciar o PostgreSQL;" -ForegroundColor Yellow
        Write-Host "  - garantir que o PostgreSQL escute apenas em 127.0.0.1." -ForegroundColor Yellow
        Write-Host ""
        Log "AVISO: PostgreSQL em modo trust (sem senha). Prosseguindo - ajuste o pg_hba.conf."
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
        $testOut2 = & $psqlExe -U postgres -d postgres -t -A -c "SELECT 1" 2>&1
        $env:PGPASSWORD = $null

        if (($testOut2 | Out-String).Trim() -notmatch "^1") {
            Log "ERRO: senha invalida ou acesso recusado: $($testOut2 | Out-String)"
            exit 1
        }
        Log "Conexao com postgres OK usando senha informada."
    }
} else {
    # Nova instalacao
    if ([string]::IsNullOrWhiteSpace($SuperSenha)) {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object byte[] 24; $rng.GetBytes($bytes)   # CSPRNG (nao Get-Random)
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
            # Verifica a assinatura Authenticode do instalador (integridade)
            $sigPg = Get-AuthenticodeSignature $InstallerExe
            if ($sigPg.Status -eq 'Valid') {
                Log "Assinatura do instalador verificada: $($sigPg.SignerCertificate.Subject)"
            } elseif ($sigPg.Status -eq 'NotSigned' -or $sigPg.Status -eq 'HashMismatch') {
                Log "ERRO: assinatura invalida no instalador do PostgreSQL ($($sigPg.Status)) - abortando."
                exit 1
            } else {
                Log "AVISO: nao foi possivel validar totalmente a assinatura do instalador PG ($($sigPg.Status)) - prosseguindo."
            }
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
    # Continue evita que stderr do psql.exe vire excecao com ErrorActionPreference=Stop
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # -t -A: saida sem cabecalho/contagem (locale-independent)
    $out = & $psqlExe -U postgres -d $db -t -A -c $sql 2>&1
    $ErrorActionPreference = $prevEAP
    $env:PGPASSWORD = $null
    return $out
}

Log "Criando usuario 'sigedash' no PostgreSQL..."
$userExiste = Psql "SELECT 1 FROM pg_roles WHERE rolname='sigedash'"
if (($userExiste | Out-String).Trim() -match "^1") {
    Log "Usuario 'sigedash' ja existe - atualizando senha."
    Psql "ALTER USER sigedash WITH PASSWORD '$SigeDashSenha'" | Out-Null
} else {
    Psql "CREATE USER sigedash WITH PASSWORD '$SigeDashSenha'" | Out-Null
    Log "Usuario 'sigedash' criado."
}

$dbExiste = Psql "SELECT 1 FROM pg_database WHERE datname='sigedash'"
if (($dbExiste | Out-String).Trim() -notmatch "^1") {
    $out = Psql "CREATE DATABASE sigedash OWNER sigedash ENCODING 'UTF8'"
    Log "Banco 'sigedash' criado: $out"
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

# --- Hardening do PostgreSQL (apenas em instalacao NOVA feita pelo instalador do SigeDash) ---
# Nao mexe em PostgreSQL pre-existente (pode ser compartilhado). Ajustes:
#  - listen_addresses = 'localhost'  (o instalador EDB deixa '*', expondo na rede)
#  - password_encryption = scram-sha-256  (padrao no PG16; garantimos)
#  - pg_hba.conf: qualquer 'trust'/'md5' local -> scram-sha-256 (no PG16 ja e scram; defesa)
$semBom = New-Object System.Text.UTF8Encoding $false
if ($freshInstall) {
    Log "Aplicando hardening do PostgreSQL (localhost-only + scram)..."
    $confFile = (Psql "SHOW config_file" | Out-String).Trim()
    $hbaFile  = (Psql "SHOW hba_file"    | Out-String).Trim()

    if ($confFile -and (Test-Path $confFile)) {
        $c = Get-Content $confFile -Raw
        $c = $c -replace "(?m)^\s*#?\s*listen_addresses\s*=.*$", "listen_addresses = 'localhost'"
        if ($c -match "(?m)^\s*#?\s*password_encryption\s*=") {
            $c = $c -replace "(?m)^\s*#?\s*password_encryption\s*=.*$", "password_encryption = scram-sha-256"
        } else { $c = $c.TrimEnd() + "`r`npassword_encryption = scram-sha-256`r`n" }
        [System.IO.File]::WriteAllText($confFile, $c, $semBom)
        Log "postgresql.conf: listen_addresses=localhost + password_encryption=scram-sha-256."
    } else { Log "AVISO: config_file nao localizado - postgresql.conf nao ajustado." }

    if ($hbaFile -and (Test-Path $hbaFile)) {
        $linhas = Get-Content $hbaFile | ForEach-Object {
            if ($_ -match "^\s*(local|host)\s") { $_ -replace "\b(trust|md5)\b(\s*)$", "scram-sha-256" } else { $_ }
        }
        [System.IO.File]::WriteAllText($hbaFile, (($linhas -join "`r`n") + "`r`n"), $semBom)
        Log "pg_hba.conf: metodos locais trust/md5 -> scram-sha-256."
    } else { Log "AVISO: hba_file nao localizado - pg_hba.conf nao ajustado." }

    if ($svcAtual) {
        Restart-Service $svcAtual.Name -Force
        Start-Sleep -Seconds 4
        Log "PostgreSQL reiniciado com o hardening."
    }
    # Revalida a conexao do sigedash apos o hardening
    $env:PGPASSWORD = $SigeDashSenha
    $rev = & $psqlExe -U sigedash -h localhost -d sigedash -t -A -c "SELECT 1" 2>&1
    $env:PGPASSWORD = $null
    if (($rev | Out-String).Trim() -match "^1") { Log "Hardening OK - sigedash conecta via scram em localhost." }
    else { Log "AVISO: conexao do sigedash falhou apos hardening: $rev - revise pg_hba/postgresql.conf." }
}

Log ""
Log "=== PostgreSQL pronto! ==="
Log "Banco   : sigedash"
Log "Usuario : sigedash"
Write-Host "Senha   : $SigeDashSenha" -ForegroundColor Yellow   # console apenas (segredo, fora do log)
Log "Porta   : 5432"
Log ""
Log "Proximo passo: execute instalar-backend.ps1 -PostgresSenha '<a senha exibida acima>'"
