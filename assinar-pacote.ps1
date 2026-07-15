<#
.SYNOPSIS
    Assina manualmente os .exe de um pacote SigeDash no servidor do CodeSign (eToken SafeNet).
    Use enquanto o pipeline Azure DevOps nao estiver disponivel.
.DESCRIPTION
    Recebe a PASTA do pacote (ex.: dist\SigeDash-Deploy-v1.0.23) OU o .zip. Assina os 3 executaveis
    (Instalar-SigeDash.exe, SigeDash.Api.exe, agente\SigeDash.Agente.exe) com signtool /csp+/k,
    verifica cada um e, se a entrada foi um .zip, regenera o .zip ASSINADO no mesmo caminho.
    O PIN nunca fica no codigo: passe -Pin ou defina $env:SIGEDASH_SIGN_PIN.
.PARAMETER Pacote
    Caminho da pasta do pacote OU do arquivo .zip a assinar.
.PARAMETER Pin
    PIN do eToken. Se omitido, usa a variavel de ambiente SIGEDASH_SIGN_PIN.
.EXAMPLE
    $env:SIGEDASH_SIGN_PIN = "<pin>"
    .\assinar-pacote.ps1 -Pacote "C:\Release\SigeDash-Deploy-v1.0.23.zip"
.EXAMPLE
    .\assinar-pacote.ps1 -Pacote "C:\...\dist\SigeDash-Deploy-v1.0.23" -Pin "<pin>"
#>
param(
    [Parameter(Mandatory)][string]$Pacote,
    [string]$Pin          = $env:SIGEDASH_SIGN_PIN,
    [string]$SignTool     = "C:\CodeSign\signtool.exe",
    [string]$CertFile     = "C:\CodeSign\SBR-CodeSign-Pub.cer",
    [string]$Csp          = "eToken Base Cryptographic Provider",
    [string]$TokenReader  = "SafeNet Token JC 0",
    [string]$KeyContainer = "396d712fbe2553ed",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($Pin))            { Write-Error "Informe -Pin ou defina SIGEDASH_SIGN_PIN."; exit 1 }
if (-not (Test-Path $SignTool))               { Write-Error "signtool nao encontrado em: $SignTool"; exit 1 }
if (-not (Test-Path $CertFile))               { Write-Error "certificado nao encontrado em: $CertFile"; exit 1 }
if (-not (Test-Path $Pacote))                 { Write-Error "pacote nao encontrado: $Pacote"; exit 1 }

# Se veio .zip, extrai para uma pasta temporaria; ao final regenera o zip assinado
$eraZip = $false
$pasta  = $Pacote
$zipOut = $null
if ($Pacote -match '\.zip$') {
    $eraZip = $true
    $zipOut = (Resolve-Path $Pacote).Path
    $pasta  = Join-Path $env:TEMP ("sd-sign-" + [IO.Path]::GetFileNameWithoutExtension($Pacote))
    if (Test-Path $pasta) { Remove-Item $pasta -Recurse -Force }
    Write-Host "Extraindo $Pacote ..."
    Expand-Archive -Path $Pacote -DestinationPath $pasta -Force
}

$exes = @(
    (Join-Path $pasta "Instalar-SigeDash.exe"),
    (Join-Path $pasta "SigeDash.Api.exe"),
    (Join-Path $pasta "agente\SigeDash.Agente.exe")
)

$key = "[$TokenReader{{$Pin}}]=p11#$KeyContainer"
$assinados = 0
foreach ($exe in $exes) {
    if (-not (Test-Path $exe)) { Write-Host "  (pulado - nao existe) $(Split-Path $exe -Leaf)" -ForegroundColor DarkYellow; continue }
    Write-Host "Assinando $(Split-Path $exe -Leaf) ..." -ForegroundColor Cyan
    & $SignTool sign /f $CertFile /csp $Csp /k $key /fd sha256 /tr $TimestampUrl /td sha256 $exe
    if ($LASTEXITCODE -ne 0) { Write-Error "Falha ao assinar '$exe' (codigo $LASTEXITCODE)"; exit 1 }
    & $SignTool verify /pa /q $exe
    if ($LASTEXITCODE -ne 0) { Write-Host "  AVISO: verificacao falhou em $(Split-Path $exe -Leaf)" -ForegroundColor Yellow }
    else { Write-Host "  OK (assinado e verificado)" -ForegroundColor Green }
    $assinados++
}

if ($assinados -eq 0) { Write-Error "Nenhum .exe encontrado no pacote para assinar."; exit 1 }

if ($eraZip) {
    Write-Host "Regerando o .zip assinado: $zipOut"
    if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
    Compress-Archive -Path "$pasta\*" -DestinationPath $zipOut -CompressionLevel Optimal
    Remove-Item $pasta -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Concluido: $assinados executavel(is) assinado(s)." -ForegroundColor Green
if ($eraZip) { Write-Host "Zip assinado pronto em: $zipOut" -ForegroundColor Green }
