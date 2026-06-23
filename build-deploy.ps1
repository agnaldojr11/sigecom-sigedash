<#
.SYNOPSIS
    Gera o pacote de deploy do SigeDash pronto para instalacao no cliente.
.DESCRIPTION
    1. Compila o backend (.NET 8, win-x64, self-contained)
    2. Compila o agente + instalador InnoSetup (se InnoSetup estiver instalado)
    3. Monta o pacote com todos os scripts de instalacao
    4. Gera SigeDash-Deploy-v{versao}.zip em dist\

    O ZIP entregue ao tecnico contem tudo que e necessario.
    O tecnico descompacta e executa: .\instalar-tudo.ps1

.PARAMETER Versao
    Versao do pacote. Padrao: 1.0.0
.PARAMETER PularAgente
    Nao compila o agente (util se InnoSetup nao estiver instalado).
.EXAMPLE
    .\build-deploy.ps1
    .\build-deploy.ps1 -Versao "1.1.0"
    .\build-deploy.ps1 -PularAgente
#>
param(
    [string]$Versao      = "1.0.0",
    [switch]$PularAgente
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
    "deploy\backend\instalar-tunnel.ps1",
    "deploy\backend\atualizar.ps1",
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

# 4. Compila agente + instalador InnoSetup
Titulo "4" "Compilando agente e instalador InnoSetup..."
$ISCC      = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$BUILD_BAT = Join-Path $ROOT "deploy\agente\build-instalador.bat"

if ($PularAgente) {
    Log "Pulando compilacao do agente (-PularAgente informado)"
} elseif (-not (Test-Path $ISCC)) {
    Write-Host "  InnoSetup nao encontrado - pulando build do agente" -ForegroundColor Yellow
    Write-Host "  Instale em: https://jrsoftware.org/isinfo.php" -ForegroundColor Yellow
} else {
    & cmd /c $BUILD_BAT
    Checar $LASTEXITCODE "build-instalador.bat"

    $agenteExe = Get-ChildItem $DIST -Filter "SigeDashAgente-Setup-*.exe" |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($agenteExe) {
        Copy-Item $agenteExe.FullName $PKG_DIR -Force
        Log "  + $($agenteExe.Name)"
    } else {
        Write-Host "  AVISO: SigeDashAgente-Setup-*.exe nao encontrado" -ForegroundColor Yellow
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

# 4c. Grava version.txt no pacote
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
- instalar-tunnel.ps1       Passo 4: instala Cloudflare Tunnel
- configurar-cliente.ps1    Passo 3: configura agente e cria usuario
- atualizar.ps1             Atualizacao automatica (agendado toda segunda 03h)
- SigeDashAgente-Setup.exe  Instalador do agente (se incluido)

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
