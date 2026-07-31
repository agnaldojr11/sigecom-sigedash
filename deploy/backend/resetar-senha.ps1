<#
.SYNOPSIS
    Redefine a senha de um usuario do SigeDash NA PROPRIA MAQUINA do cliente (recuperacao).
.DESCRIPTION
    Use quando o ADM (ou qualquer usuario) perdeu a senha e nao ha outro admin para reseta-lo
    pela tela. Roda LOCALMENTE no servidor do cliente: le a AdminKey do appsettings e chama o
    endpoint local /admin/reset-senha (bloqueado para acesso externo). Gera uma senha temporaria
    (troca obrigatoria no proximo login).

    Execute como Administrador, no servidor onde o SigeDash Backend esta instalado.
.PARAMETER Login
    Login do usuario a resetar. Padrao: admin (o ADM inicial da empresa).
.PARAMETER Cliente
    Nome da empresa. Opcional se houver apenas 1 cliente cadastrado (caso normal no servidor do cliente).
.PARAMETER BackendUrl
    URL local do backend. Padrao: http://localhost:5000
.PARAMETER AppSettings
    Caminho do appsettings.Production.json (de onde a AdminKey e lida).
.EXAMPLE
    .\resetar-senha.ps1
    .\resetar-senha.ps1 -Login gerente
#>
param(
    [string]$Login       = "admin",
    [string]$Cliente     = "",
    [string]$BackendUrl  = "http://localhost:5000",
    [string]$AppSettings = "C:\SigeDash\Backend\appsettings.Production.json"
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $AppSettings)) { Write-Error "appsettings nao encontrado: $AppSettings"; exit 1 }
$cfg = Get-Content $AppSettings -Raw | ConvertFrom-Json
$adminKey = $cfg.AdminKey
if ([string]::IsNullOrWhiteSpace($adminKey)) { Write-Error "AdminKey ausente no appsettings ($AppSettings)."; exit 1 }

$body = @{ login = $Login }
if ($Cliente) { $body["cliente"] = $Cliente }
$json = $body | ConvertTo-Json

try {
    $resp = Invoke-RestMethod -Uri "$BackendUrl/admin/reset-senha" -Method POST `
        -Headers @{ "X-Admin-Key" = $adminKey; "Content-Type" = "application/json" } -Body $json
} catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    Write-Error "Falha ao resetar a senha: $msg"
    exit 2
}

$barra = "=" * 60
Write-Host ""
Write-Host $barra -ForegroundColor Green
Write-Host "  SENHA REDEFINIDA - entregue ao usuario:" -ForegroundColor Green
Write-Host "    Empresa : $($resp.cliente)" -ForegroundColor White
Write-Host "    Login   : $($resp.login)" -ForegroundColor White
Write-Host "    Senha   : $($resp.senhaTemporaria)" -ForegroundColor Yellow
Write-Host "  (a troca de senha e OBRIGATORIA no proximo login)" -ForegroundColor DarkYellow
Write-Host $barra -ForegroundColor Green
Write-Host ""
