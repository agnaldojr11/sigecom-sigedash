<#
.SYNOPSIS
    Gera o pacote de deploy do SigeDash pronto para instalacao no cliente.
.DESCRIPTION
    1. Compila o backend (.NET 8, win-x64, self-contained)
    2. Compila o agente (.NET 4.8) para a subpasta 'agente' do pacote
    3. Monta o pacote com todos os scripts de instalacao
    4. (Opcional, -Assinar) Assina os .exe com o certificado EV (DigiCert no token)
    5. Gera SigeDash-Deploy-v{versao}.zip em dist\

    O ZIP entregue ao tecnico contem tudo que e necessario.
    O tecnico descompacta e executa: .\instalar-tudo.ps1

.PARAMETER Versao
    Versao do pacote. Padrao: 1.0.0
.PARAMETER PularAgente
    Nao compila o agente (gera pacote apenas com backend).
.PARAMETER Assinar
    Assina Instalar-SigeDash.exe, SigeDash.Api.exe e SigeDash.Agente.exe no eToken SafeNet.
    Exige o token conectado e a variavel de ambiente SIGEDASH_SIGN_PIN (o PIN do token).
.PARAMETER CertFile
    Caminho do .cer publico. Padrao: C:\CodeSign\SBR-CodeSign-Pub.cer (servidor de build).
.PARAMETER Csp / TokenReader / KeyContainer
    Parametros do token SafeNet (CSP, nome do leitor e container p11). Padroes = cert da SistemasBr.
.PARAMETER TimestampUrl
    Servidor de timestamp RFC3161. Padrao: http://timestamp.digicert.com
.EXAMPLE
    .\build-deploy.ps1
    .\build-deploy.ps1 -Versao "1.1.0" -PularAgente
    # Assinado (no servidor de build, com o token): defina o PIN e rode com -Assinar
    $env:SIGEDASH_SIGN_PIN = "<pin-do-token>"; .\build-deploy.ps1 -Versao "1.0.22" -Assinar
#>
param(
    [string]$Versao      = "1.0.0",
    [switch]$PularAgente,

    # Assinatura de codigo (eToken SafeNet, via CSP + key container). Opt-in: exige o token conectado.
    # O PIN NUNCA fica no codigo - vem da variavel de ambiente SIGEDASH_SIGN_PIN (secret do pipeline).
    # Os defaults espelham o servidor de build do SIGECOM (C:\CodeSign).
    [switch]$Assinar,
    [string]$SignTool     = "",                                 # vazio = auto (Resolve-SignTool)
    [string]$CertFile     = "C:\CodeSign\SBR-CodeSign-Pub.cer",
    [string]$Csp          = "eToken Base Cryptographic Provider",
    [string]$TokenReader  = "SafeNet Token JC 0",
    [string]$KeyContainer = "396d712fbe2553ed",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
$ROOT    = $PSScriptRoot
$DIST    = Join-Path $ROOT "dist"
$PUBLISH = Join-Path $DIST "_publish_backend"
$PKG_NAME = "SigeDash-Deploy-v$Versao"
$PKG_DIR  = Join-Path $DIST $PKG_NAME
$ZIP_OUT  = Join-Path $DIST "$PKG_NAME.zip"

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $msg"
}

function Titulo($n, $msg) {
    Write-Host ""
    Write-Host "[$n] $msg" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Checar($exitCode, $etapa) {
    if ($exitCode -ne 0) {
        Write-Host "ERRO em '$etapa' (codigo $exitCode)" -ForegroundColor Red
        exit 1
    }
}

# Localiza o signtool.exe: -SignTool -> C:\CodeSign -> assinatura\ do repo -> cache -> Windows SDK -> NuGet.
function Resolve-SignTool {
    if ($SignTool -and (Test-Path $SignTool)) { return $SignTool }
    foreach ($cand in @(
        "C:\CodeSign\signtool.exe",
        (Join-Path $ROOT "assinatura\signtool.exe"),
        (Join-Path $ROOT ".tools\signtool\signtool.exe")
    )) { if (Test-Path $cand) { return $cand } }

    $kit = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1
    if ($kit) { return $kit.FullName }

    Log "signtool nao encontrado - baixando Microsoft.Windows.SDK.BuildTools (NuGet)..."
    $toolsDir = Join-Path $ROOT ".tools"
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
    $nupkg   = Join-Path $toolsDir "sdk-buildtools.zip"
    $extract = Join-Path $toolsDir "sdk-buildtools"
    Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.BuildTools" `
                      -OutFile $nupkg -UseBasicParsing
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $nupkg -DestinationPath $extract -Force
    $dl = Get-ChildItem $extract -Recurse -Filter signtool.exe |
          Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $dl) { throw "signtool.exe nao encontrado no pacote NuGet baixado" }
    New-Item -ItemType Directory -Force -Path (Split-Path $cache) | Out-Null
    Copy-Item $dl.FullName $cache -Force
    return $cache
}

# Assina e verifica um executavel no eToken SafeNet (CSP + key container), com timestamp.
# Espelha o SIGECOM: signtool sign /f <cer> /csp "<CSP>" /k "[<reader>{{PIN}}]=p11#<container>" <exe>
# O PIN vem de $env:SIGEDASH_SIGN_PIN (secret) - nunca do codigo. Timestamp adicionado (nao ha no SIGECOM).
function Assinar($signtool, $arquivo) {
    $pin = $env:SIGEDASH_SIGN_PIN
    if ([string]::IsNullOrEmpty($pin)) {
        throw "PIN do token ausente. Defina a variavel de ambiente SIGEDASH_SIGN_PIN (secret do pipeline) antes de assinar."
    }
    $key = "[$TokenReader{{$pin}}]=p11#$KeyContainer"
    & $signtool sign /f $CertFile /csp $Csp /k $key /fd sha256 /tr $TimestampUrl /td sha256 $arquivo
    if ($LASTEXITCODE -ne 0) { throw "Falha ao assinar '$arquivo' (codigo $LASTEXITCODE)" }
    & $signtool verify /pa /q $arquivo
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  AVISO: verificacao da assinatura falhou em $arquivo" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  SigeDash - Build do Pacote de Deploy v$Versao" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green

# Limpa saidas anteriores
Titulo "0" "Limpando dist anterior..."
New-Item -ItemType Directory -Path $DIST -Force | Out-Null
if (Test-Path $PUBLISH) { Remove-Item $PUBLISH -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $PKG_DIR) { Remove-Item $PKG_DIR  -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $ZIP_OUT) { Remove-Item $ZIP_OUT  -Force   -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $PKG_DIR -Force | Out-Null
Log "OK"

# 1. Compila o backend
Titulo "1" "Compilando backend (win-x64, self-contained)..."
$BACKEND_PROJ = Join-Path $ROOT "backend\src\SigeDash.Api\SigeDash.Api.csproj"

dotnet publish $BACKEND_PROJ `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $PUBLISH `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -p:PublishSingleFile=false

Checar $LASTEXITCODE "dotnet publish backend"
Log "Backend publicado em: $PUBLISH"

# 2. Copia backend para o pacote
Titulo "2" "Copiando backend para o pacote..."
Copy-Item "$PUBLISH\*" $PKG_DIR -Recurse -Force
$qtd = (Get-ChildItem $PKG_DIR -Recurse).Count
Log "OK - $qtd arquivos copiados"

# 3. Copia scripts de instalacao
Titulo "3" "Copiando scripts de instalacao..."
$SCRIPTS = @(
    "deploy\backend\iniciar.cmd",
    "deploy\backend\instalar-tudo.ps1",
    "deploy\backend\instalar-postgres.ps1",
    "deploy\backend\instalar-backend.ps1",
    "deploy\backend\instalar-agente.ps1",
    "deploy\backend\instalar-tunnel.ps1",
    "deploy\backend\atualizar.ps1",
    "deploy\backend\rotacionar-segredos.ps1",
    "deploy\agente\configurar-cliente.ps1"
)

foreach ($s in $SCRIPTS) {
    $src = Join-Path $ROOT $s
    if (Test-Path $src) {
        Copy-Item $src $PKG_DIR -Force
        Log "  + $(Split-Path $s -Leaf)"
    } else {
        Write-Host "  AVISO: $s nao encontrado" -ForegroundColor Yellow
    }
}

# 3b. Re-salva scripts com UTF-8 BOM para evitar parse errors no PS 5.1 do cliente
Titulo "3b" "Gravando UTF-8 BOM nos scripts..."
$utf8Bom = New-Object System.Text.UTF8Encoding $true
Get-ChildItem $PKG_DIR -Filter "*.ps1" | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($_.FullName, $content, $utf8Bom)
    Log "  BOM: $($_.Name)"
}

# 4. Compila o agente (binarios .NET 4.8) para a subpasta 'agente' do pacote
# Nao usa mais InnoSetup: o agente e instalado por instalar-agente.ps1 (nao-interativo).
Titulo "4" "Compilando agente (binarios .NET 4.8 win-x64)..."
$AGENTE_PROJ = Join-Path $ROOT "agente\SigeDash.Agente\SigeDash.Agente.csproj"
$AGENTE_OUT  = Join-Path $PKG_DIR "agente"

if ($PularAgente) {
    Log "Pulando compilacao do agente (-PularAgente informado)"
} elseif (-not (Test-Path $AGENTE_PROJ)) {
    Write-Host "  AVISO: projeto do agente nao encontrado em $AGENTE_PROJ" -ForegroundColor Yellow
} else {
    dotnet publish $AGENTE_PROJ `
        -c Release `
        -r win-x64 `
        --self-contained false `
        -o $AGENTE_OUT `
        -p:DebugType=None `
        -p:DebugSymbols=false

    Checar $LASTEXITCODE "dotnet publish agente"

    if (Test-Path (Join-Path $AGENTE_OUT "SigeDash.Agente.exe")) {
        $qtdAg = (Get-ChildItem $AGENTE_OUT -Recurse).Count
        Log "Agente publicado em: $AGENTE_OUT ($qtdAg arquivos)"
    } else {
        Write-Host "  AVISO: SigeDash.Agente.exe nao encontrado apos publish" -ForegroundColor Yellow
    }
}

# 4b. Inclui cf.json (credenciais Cloudflare) se existir
$cfJson = Join-Path $ROOT "deploy\cf.json"
if (Test-Path $cfJson) {
    Copy-Item $cfJson $PKG_DIR -Force
    Log "cf.json incluido (tunnel automatico habilitado)."
} else {
    Write-Host "  AVISO: deploy\cf.json nao encontrado - tunnel precisara de token manual." -ForegroundColor Yellow
    Write-Host "  Execute .\configurar-cf.ps1 para habilitar criacao automatica de tunnels." -ForegroundColor Yellow
}

# 4d. Gera Instalar-SigeDash.exe via ps2exe
Titulo "4d" "Gerando Instalar-SigeDash.exe..."
$ps2exeModule = Get-Module -ListAvailable ps2exe | Select-Object -First 1
if ($ps2exeModule) {
    $launcherSrc = Join-Path $env:TEMP "sigedash-launcher.ps1"
    $exePath     = Join-Path $PKG_DIR "Instalar-SigeDash.exe"

    # Script minimo que o exe vai executar.
    # IMPORTANTE: em exe do ps2exe, $PSScriptRoot/$PSCommandPath vem VAZIO. Por isso usamos
    # o caminho real do processo (o proprio exe) via MainModule.FileName para achar os .ps1.
    $launcherLines = @(
        '$exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)',
        'Get-ChildItem "$exeDir\*.ps1" -ErrorAction SilentlyContinue | Unblock-File',
        '$instalador = Join-Path $exeDir "instalar-tudo.ps1"',
        'if (-not (Test-Path $instalador)) {',
        '    Write-Host "ERRO: instalar-tudo.ps1 nao encontrado em $exeDir" -ForegroundColor Red',
        '    Read-Host "Pressione Enter para fechar"; exit 1',
        '}',
        '# Roda em processo filho: isola o "exit" do script e garante a pausa final para ler o erro.',
        '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $instalador',
        'Write-Host ""',
        'Read-Host "Pressione Enter para fechar"'
    )
    $launcherLines | Out-File $launcherSrc -Encoding UTF8

    Import-Module ps2exe -ErrorAction SilentlyContinue
    $versaoExe = "$Versao.0"   # ps2exe exige formato X.X.X.X
    Invoke-ps2exe `
        -InputFile    $launcherSrc `
        -OutputFile   $exePath `
        -requireAdmin `
        -title        "SigeDash Instalador" `
        -description  "Instalacao automatica do SigeDash - SistemasBr" `
        -company      "SistemasBr" `
        -product      "SigeDash" `
        -version      $versaoExe

    Remove-Item $launcherSrc -ErrorAction SilentlyContinue

    if (Test-Path $exePath) {
        $exeSizeKB = [math]::Round((Get-Item $exePath).Length / 1KB, 0)
        Log "Instalar-SigeDash.exe gerado (${exeSizeKB} KB)."
    } else {
        Write-Host "  AVISO: falha ao gerar exe - iniciar.cmd disponivel como alternativa." -ForegroundColor Yellow
    }
} else {
    Write-Host "  AVISO: ps2exe nao instalado - pulando geracao do exe." -ForegroundColor Yellow
    Write-Host "  Execute: Install-Module ps2exe -Force -Scope CurrentUser" -ForegroundColor Yellow
}

# 4e. Assina os executaveis com o certificado EV (DigiCert no token).
#     Opt-in (-Assinar): exige o token conectado; o middleware solicita o PIN.
if ($Assinar) {
    Titulo "4e" "Assinando executaveis (certificado EV)..."
    $signtool = Resolve-SignTool
    Log "signtool    : $signtool"
    Log "Certificado : $CertFile"
    Log "Token/CSP   : $Csp | container p11#$KeyContainer"
    Log "Timestamp   : $TimestampUrl"

    $exesParaAssinar = @(
        (Join-Path $PKG_DIR "Instalar-SigeDash.exe"),
        (Join-Path $PKG_DIR "SigeDash.Api.exe"),
        (Join-Path $PKG_DIR "agente\SigeDash.Agente.exe")
    )

    $assinados = 0
    foreach ($exe in $exesParaAssinar) {
        if (Test-Path $exe) {
            Log "  Assinando $(Split-Path $exe -Leaf)..."
            Assinar $signtool $exe
            $assinados++
        }
    }
    Log "Assinatura concluida ($assinados executaveis)."
} else {
    Write-Host ""
    Write-Host "[4e] Assinatura PULADA. Rode com -Assinar (token EV conectado) para assinar os .exe." -ForegroundColor DarkYellow
}

# 4f. Grava version.txt no pacote
$versionPath = Join-Path $PKG_DIR "version.txt"
$Versao | Out-File $versionPath -Encoding UTF8 -NoNewline
Log "version.txt: $Versao"

# 5. Cria README de instalacao
Titulo "5" "Gerando README-INSTALACAO.txt..."
$readme = "SigeDash - Pacote de Deploy v$Versao
=====================================

INSTRUCOES RAPIDAS
------------------
1. Copie esta pasta para o servidor Windows do cliente
2. Abra o PowerShell como Administrador
3. Execute (substitua os valores em maiusculas):

   .\instalar-tudo.ps1 ``
       -NomeCliente `"NOME DO CLIENTE`" ``
       -FdbPath `"C:\CAMINHO\PARA\BANCO.FDB`" ``
       -TunnelToken `"TOKEN_DO_CLOUDFLARE`"

   Para obter o TunnelToken:
   1. Acesse https://one.dash.cloudflare.com
   2. Zero Trust -> Networks -> Tunnels -> Create a tunnel
   3. Nome: sigedash-[cliente]  |  Service: HTTP  |  URL: localhost:5000
   4. Copie o token exibido

PRE-REQUISITOS NO SERVIDOR
--------------------------
- Windows 10/11 ou Windows Server 2016+
- Acesso de Administrador
- Sigecom + Firebird 2.5 ja instalados e funcionando
- Internet ativa (para download do PostgreSQL e Cloudflare)

CONTEUDO DESTA PASTA
--------------------
- SigeDash.Api.exe          Backend + PWA (registrado como Windows Service)
- wwwroot/                  Arquivos do app web (servidos pelo backend)
- instalar-tudo.ps1         Script principal - execute este
- instalar-postgres.ps1     Passo 1: instala PostgreSQL 16
- instalar-backend.ps1      Passo 2: registra backend como Windows Service
- instalar-agente.ps1       Passo 3: instala o agente (binarios + servico)
- configurar-cliente.ps1    Registra o cliente no backend e grava o config do agente
- instalar-tunnel.ps1       Passo 4: instala Cloudflare Tunnel
- atualizar.ps1             Atualizacao automatica (agendado toda segunda 03h)
- agente/                   Binarios do agente (.NET 4.8) instalados pelo instalar-agente.ps1

SERVICOS INSTALADOS NO SERVIDOR DO CLIENTE
------------------------------------------
- postgresql-x64-16     Banco de dados local
- SigeDashBackend       API + PWA (porta 5000)
- SigeDashAgente        Coleta dados do Firebird
- cloudflared           Tunel Cloudflare (acesso externo HTTPS)

SUPORTE
-------
SistemasBr - suporte@sistemasbr.net
"

$readmePath = Join-Path $PKG_DIR "README-INSTALACAO.txt"
$utf8Nobom  = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($readmePath, $readme, $utf8Nobom)
Log "README criado."

# 6. Gera o ZIP
Titulo "6" "Compactando pacote: $PKG_NAME.zip..."
Compress-Archive -Path "$PKG_DIR\*" -DestinationPath $ZIP_OUT -CompressionLevel Optimal
$zipSizeMB = [math]::Round((Get-Item $ZIP_OUT).Length / 1MB, 1)
Log "ZIP gerado: $ZIP_OUT ($zipSizeMB MB)"

# Resumo
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Pacote pronto!" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host ""
Write-Host "  Arquivo : $ZIP_OUT" -ForegroundColor White
Write-Host "  Tamanho : $zipSizeMB MB" -ForegroundColor White
Write-Host ""
Write-Host "  Entregue o ZIP ao tecnico responsavel pela instalacao." -ForegroundColor Yellow
Write-Host "  Instrucoes: README-INSTALACAO.txt dentro do ZIP." -ForegroundColor Yellow
Write-Host ""
