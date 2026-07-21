<#
.SYNOPSIS
    Assina manualmente os .exe de um pacote SigeDash no servidor do CodeSign (eToken SafeNet / CNG KSP).
.DESCRIPTION
    A chave privada do eToken vive no CNG KSP "SafeNet Smart Card Key Storage Provider".
    Por isso a assinatura usa SELECAO PELO STORE (signtool /sha1 do thumbprint), e NAO o /csp+/k legado
    (que falha com "No private key is available" porque nao enxerga chaves do KSP/CNG).

    Regras de seguranca deste script (evitam bloquear o PIN do token):
      - 1 TENTATIVA por arquivo. Sem retry automatico. Se falhar, PARA e mostra a saida.
      - SEM PIN embutido no comando. O SafeNet pede o PIN; habilite "single logon" no
        SafeNet Authentication Client para assinar varios sem redigitar.

    Recebe a PASTA do pacote OU o .zip. Assina os 3 executaveis (Instalar-SigeDash.exe,
    SigeDash.Api.exe, agente\SigeDash.Agente.exe), verifica cada um e, se a entrada foi um
    .zip, regenera o .zip ASSINADO no mesmo caminho.
.PARAMETER Pacote
    Caminho da pasta do pacote OU do arquivo .zip a assinar.
.PARAMETER Thumbprint
    Thumbprint (SHA1) do certificado de code signing no store CurrentUser\My.
    Se omitido, usa $env:SIGEDASH_SIGN_THUMBPRINT; se ainda vazio, autodetecta o unico
    certificado de code signing valido (nao expirado) do store.
.EXAMPLE
    .\assinar-pacote.ps1 -Pacote "C:\Release\SigeDash-Deploy-v1.0.23.zip"
.EXAMPLE
    .\assinar-pacote.ps1 -Pacote "C:\...\SigeDash-Deploy-v1.0.23" -Thumbprint "AABBCCDD..."
.NOTES
    Pre-requisito: token conectado e DESTRAVADO, com o certificado importado no store do
    usuario atual. Descubra o thumbprint com:
      Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject,Thumbprint,NotAfter
#>
param(
    [Parameter(Mandatory)][string]$Pacote,
    [string]$Thumbprint   = $env:SIGEDASH_SIGN_THUMBPRINT,
    [string]$SignTool     = "C:\CodeSign\signtool.exe",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SignTool)) { Write-Error "signtool nao encontrado em: $SignTool"; exit 1 }
if (-not (Test-Path $Pacote))   { Write-Error "pacote nao encontrado: $Pacote"; exit 1 }

# Resolve o certificado no store CurrentUser (a chave privada vem do CNG KSP do token).
function Resolve-Thumbprint {
    param([string]$Thumb)
    if (-not [string]::IsNullOrWhiteSpace($Thumb)) {
        return ($Thumb -replace '[^0-9A-Fa-f]', '').ToUpper()
    }
    $certs = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
             Where-Object { $_.NotAfter -gt (Get-Date) -and $_.NotBefore -le (Get-Date) }
    if (-not $certs) {
        throw "Nenhum certificado de code signing valido em Cert:\CurrentUser\My. O token esta conectado e destravado?"
    }
    if (@($certs).Count -gt 1) {
        Write-Host "Mais de um certificado de code signing valido encontrado:" -ForegroundColor Yellow
        $certs | ForEach-Object { Write-Host "  $($_.Thumbprint)  $($_.Subject)  (exp $($_.NotAfter.ToString('dd/MM/yyyy')))" }
        throw "Informe -Thumbprint para escolher (ou defina SIGEDASH_SIGN_THUMBPRINT)."
    }
    Write-Host "Certificado: $($certs.Subject) (exp $($certs.NotAfter.ToString('dd/MM/yyyy')))" -ForegroundColor DarkCyan
    return $certs.Thumbprint.ToUpper()
}

$Thumbprint = Resolve-Thumbprint -Thumb $Thumbprint
Write-Host "Thumbprint: $Thumbprint" -ForegroundColor DarkCyan

# Se veio .zip, extrai para uma pasta temporaria; ao final regenera o zip assinado.
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

$assinados = 0
foreach ($exe in $exes) {
    if (-not (Test-Path $exe)) { Write-Host "  (pulado - nao existe) $(Split-Path $exe -Leaf)" -ForegroundColor DarkYellow; continue }
    $nome = Split-Path $exe -Leaf
    Write-Host "Assinando $nome ..." -ForegroundColor Cyan

    # Evita que stderr do signtool vire excecao (EAP=Stop) antes de checarmos o codigo.
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"

    # 1 TENTATIVA (sem retry): seleciona o cert pelo store; o CNG KSP do token fornece a chave.
    $out = & $SignTool sign /sha1 $Thumbprint /fd sha256 /tr $TimestampUrl /td sha256 $exe 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        Write-Host "  signtool falhou (codigo $rc). Saida:" -ForegroundColor Red
        $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        $ErrorActionPreference = $prevEAP
        throw "Falha ao assinar '$nome'. NAO ha retry (protege o PIN do token). Confira token/PIN/thumbprint e rode de novo."
    }
    $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $vout = & $SignTool verify /pa $exe 2>&1
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  AVISO: verify falhou em $nome. Saida:" -ForegroundColor Yellow
        $vout | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    } else {
        Write-Host "  OK (assinado e verificado)" -ForegroundColor Green
    }
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
