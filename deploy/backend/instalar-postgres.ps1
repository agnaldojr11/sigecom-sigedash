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

# Windows Server antigo (2012R2/2016) usa TLS 1.0/1.1 por padrao no .NET, e EDB/GitHub exigem TLS 1.2+.
# Sem isto o download falha com "Could not create SSL/TLS secure channel". Habilita TLS 1.2 (e 1.3 se houver).
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13 } catch {}

$PG_VERSION    = "16"
$PG_INSTALLDIR = "C:\Program Files\PostgreSQL\$PG_VERSION"
$PG_SVC        = "postgresql-x64-$PG_VERSION"
# Pasta temporaria SEGURA: o %TEMP% do usuario pode ter nome curto (USUARIO~2)/acento, que quebra
# cmdlets que resolvem curinga (Get-AuthenticodeSignature, Test-Path, Remove-Item...).
$TMP_SEG       = $(if (Test-Path "C:\Windows\Temp") { "C:\Windows\Temp" } else { $env:TEMP })
$LOG_FILE      = Join-Path $TMP_SEG "sigedash-postgres-install.log"

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

# ---------------------------------------------------------------------------------------------
# Acesso de superusuario ao PostgreSQL SEM NUNCA pedir senha. O wizard roda o PowerShell com o
# console OCULTO: qualquer prompt (Read-Host, ou o psql pedindo senha) trava a instalacao para
# sempre. Por isso todo psql usa -w (falha rapido em vez de perguntar).
# ---------------------------------------------------------------------------------------------
function TestaLoginPg($senha) {
    if (-not $psqlExe) { return $false }
    $env:PGPASSWORD = $senha
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $o = & $psqlExe -U postgres -h localhost -d postgres -w -t -A -c "SELECT 1" 2>&1
    $ErrorActionPreference = $prev
    $env:PGPASSWORD = $null
    return (($o | Out-String).Trim() -match "^1")
}

# Pasta de dados do PostgreSQL (lida do comando do servico: -D "...").
function DataDirPg() {
    $svc = Get-Service | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
    if ($svc) {
        $ip = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)" -ErrorAction SilentlyContinue).ImagePath
        if ($ip -match '-D\s+"([^"]+)"') { return $Matches[1] }
        if ($ip -match '-D\s+(\S+)')     { return $Matches[1] }
    }
    foreach ($v in @("17","16","15","14","13")) {
        $d = "C:\Program Files\PostgreSQL\$v\data"
        if (Test-Path -LiteralPath (Join-Path $d "pg_hba.conf")) { return $d }
    }
    return $null
}

function ReiniciarPg() {
    $svc = Get-Service | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
    if ($svc) { Restart-Service $svc.Name -Force -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Seconds 2; if (TestaTCP 5432) { break } }
    Start-Sleep -Seconds 2
}

# REINSTALACAO: a senha do 'postgres' foi gerada aleatoria na 1a instalacao e nao fica salva.
# Como somos Administrador, liberamos acesso LOCAL temporario so para o usuario postgres
# (127.0.0.1/::1, trust), fazemos o trabalho e restauramos o pg_hba.conf original ao final.
# NAO alteramos a senha do postgres (um PostgreSQL de terceiros continua funcionando igual).
$script:pgHbaTemp   = $null
$script:pgHbaBak = $null
function AbrirAcessoTemporario() {
    $dd = DataDirPg
    if (-not $dd) { Log "AVISO: pasta de dados do PostgreSQL nao localizada."; return $false }
    $hba = Join-Path $dd "pg_hba.conf"
    if (-not (Test-Path -LiteralPath $hba)) { Log "AVISO: pg_hba.conf nao encontrado em $dd."; return $false }
    $bak = "$hba.sigedash-bak"
    try {
        Copy-Item -LiteralPath $hba -Destination $bak -Force
        $orig = [System.IO.File]::ReadAllText($hba)
        $temp = "# SIGEDASH-TEMP: acesso local temporario do instalador (removido ao final)`r`n" +
                "host    all    postgres    127.0.0.1/32    trust`r`n" +
                "host    all    postgres    ::1/128         trust`r`n"
        [System.IO.File]::WriteAllText($hba, $temp + $orig, (New-Object System.Text.UTF8Encoding $false))
    } catch { Log "AVISO: nao consegui ajustar o pg_hba.conf: $_"; return $false }
    $script:pgHbaTemp = $hba; $script:pgHbaBak = $bak
    ReiniciarPg
    if (TestaLoginPg "") { return $true }
    FecharAcessoTemporario
    return $false
}

function FecharAcessoTemporario() {
    if (-not $script:pgHbaBak) { return }
    try {
        Copy-Item -LiteralPath $script:pgHbaBak -Destination $script:pgHbaTemp -Force
        Remove-Item -LiteralPath $script:pgHbaBak -Force -ErrorAction SilentlyContinue
        Log "Acesso temporario ao PostgreSQL desfeito (pg_hba.conf original restaurado)."
    } catch { Log "AVISO: nao consegui restaurar o pg_hba.conf ($_). Backup em $($script:pgHbaBak)" }
    $script:pgHbaBak = $null
    ReiniciarPg
}

# Qualquer erro inesperado: desfaz o acesso temporario antes de sair.
trap { FecharAcessoTemporario; break }

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

    # Servico parado parece "senha errada": garante o PostgreSQL no ar ANTES de testar o acesso.
    if ($pgSvcAtual -and $pgSvcAtual.Status -ne 'Running') {
        Log "Servico $($pgSvcAtual.Name) esta $($pgSvcAtual.Status) - iniciando..."
        try { Start-Service $pgSvcAtual.Name -ErrorAction Stop } catch { Log "AVISO: nao consegui iniciar $($pgSvcAtual.Name): $_" }
        for ($i = 0; $i -lt 15 -and -not (TestaTCP 5432); $i++) { Start-Sleep -Seconds 2 }
    }

    # Acesso de superusuario SEM prompt. Ordem: 1) trust; 2) -SuperSenha informado;
    # 3) recuperacao automatica (acesso local temporario) - caso normal de REINSTALACAO.
    if (TestaLoginPg "") {
        $SuperSenha = ""
        Log "AVISO: PostgreSQL aceita conexao local SEM SENHA (modo trust). Recomendado ajustar o pg_hba.conf."
    } elseif (-not [string]::IsNullOrWhiteSpace($SuperSenha) -and (TestaLoginPg $SuperSenha)) {
        Log "Conexao com postgres OK (senha informada por parametro)."
    } else {
        Log "Senha do 'postgres' desconhecida (normal em REINSTALACAO: ela e aleatoria e nao fica salva)."
        Log "Liberando acesso local temporario para configurar o banco (desfeito ao final)..."
        if (-not (AbrirAcessoTemporario)) {
            Log "ERRO: nao consegui acesso de superusuario ao PostgreSQL ja instalado."
            Log "Solucao: rode desinstalar-tudo.ps1 -RemoverPostgres e instale de novo, ou informe -SuperSenha."
            exit 1
        }
        $SuperSenha = ""
        Log "Acesso temporario OK."
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
    if ([string]::IsNullOrWhiteSpace($InstallerExe) -or -not (Test-Path -LiteralPath $InstallerExe)) {
        $downloadUrl  = "https://get.enterprisedb.com/postgresql/postgresql-16.9-1-windows-x64.exe"
        $InstallerExe = Join-Path $TMP_SEG "postgresql-16-windows-x64.exe"

        Log "Baixando PostgreSQL $PG_VERSION..."
        Log "(Isso pode levar alguns minutos)"

        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($downloadUrl, $InstallerExe)
            Log "Download concluido: $InstallerExe"
            # Verifica a assinatura Authenticode do instalador (integridade)
            $sigPg = Get-AuthenticodeSignature -LiteralPath $InstallerExe
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
    # --install_runtimes 1: em maquina limpa o cluster nao inicializa sem o Visual C++
    # Redistributable (initcluster falha -> instalador "completa" mas sai com codigo 1).
    $installerArgs = "--mode unattended " +
        "--superpassword `"$SuperSenha`" " +
        "--servicename $PG_SVC " +
        "--servicepassword `"$SuperSenha`" " +
        "--serverport 5432 " +
        "--datadir `"$PG_INSTALLDIR\data`" " +
        "--install_runtimes 1"

    $proc = Start-Process -FilePath $InstallerExe -ArgumentList $installerArgs -Wait -PassThru
    $exitPg = $proc.ExitCode

    # O instalador EDB as vezes retorna != 0 mesmo instalando OK (falha em script pos-install).
    # Nao abortamos so pelo codigo: verificamos se o PostgreSQL ficou REALMENTE funcional.
    if ($exitPg -ne 0) {
        Log "AVISO: instalador retornou codigo $exitPg. Verificando se o PostgreSQL ficou funcional..."
        Start-Sleep -Seconds 5
        $svcPos  = Get-Service | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
        $tcpPos  = TestaTCP 5432
        $psqlPos = Test-Path "$PG_INSTALLDIR\bin\psql.exe"
        if (-not ($psqlPos -and ($svcPos -or $tcpPos))) {
            Log "ERRO: instalador retornou $exitPg e o PostgreSQL NAO ficou funcional (servico/porta/psql ausentes)."
            Log "Logs do instalador: %TEMP%\install-postgresql.log e %TEMP%\bitrock_installer*.log"
            Log "Causa comum: Visual C++ Redistributable ausente. Instale o vc_redist.x64 e rode novamente."
            exit 1
        }
        Log "PostgreSQL ficou funcional apesar do codigo $exitPg - prosseguindo."
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
    # -t -A: saida sem cabecalho/contagem (locale-independent); -w: nunca pede senha (nao trava)
    $out = & $psqlExe -U postgres -h localhost -d $db -w -t -A -c $sql 2>&1
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
$prevEAPt = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$teste = & $psqlExe -U sigedash -h localhost -d sigedash -w -c "SELECT version()" 2>&1
$ErrorActionPreference = $prevEAPt
$env:PGPASSWORD = $null

if ($teste -match "PostgreSQL") {
    Log "Conexao OK - PostgreSQL respondendo para o usuario 'sigedash'."
} else {
    Log "ERRO: nao foi possivel conectar como usuario 'sigedash': $teste"
    Log "O banco pode estar com configuracao pg_hba.conf impedindo conexao local."
    FecharAcessoTemporario
    exit 1
}

# Reinstalacao: terminou o trabalho de superusuario -> desfaz o acesso local temporario agora.
FecharAcessoTemporario

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
    $prevEAPr = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $rev = & $psqlExe -U sigedash -h localhost -d sigedash -w -t -A -c "SELECT 1" 2>&1
    $ErrorActionPreference = $prevEAPr
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

# Sucesso explicito: o orquestrador decide pelo $LASTEXITCODE, que senao seria o do ultimo
# comando nativo executado aqui (ex.: icacls/psql), gerando falso "falhou com codigo N".
exit 0
