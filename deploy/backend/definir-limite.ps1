<#
.SYNOPSIS
    Define/ajusta o limite de dispositivos (usuarios/seats) do plano NA MAQUINA do cliente.
.DESCRIPTION
    Use quando o cliente compra mais licencas (ou para corrigir o limite). Roda LOCALMENTE no
    servidor do cliente: le a AdminKey do appsettings e chama o endpoint local
    /admin/limite-dispositivos (bloqueado para acesso externo pelo tunnel).

    O admin do cliente NAO consegue alterar o limite pelo app — apenas visualiza. So a SistemasBr,
    rodando este script no servidor, muda o numero.

    Execute como Administrador, no servidor onde o SigeDash Backend esta instalado.
.PARAMETER Limite
    Quantidade de dispositivos/usuarios liberados. 0 = ilimitado.
.PARAMETER Cliente
    Nome da empresa. Opcional se houver apenas 1 cliente cadastrado (caso normal no servidor).
.PARAMETER BackendUrl
    URL local do backend. Padrao: http://localhost:5000
.PARAMETER AppSettings
    Caminho do appsettings.Production.json (de onde a AdminKey e lida).
.EXAMPLE
    .\definir-limite.ps1 -Limite 5
    .\definir-limite.ps1 -Limite 0          # ilimitado
#>
param(
    [Parameter(Mandatory)]
    [int]$Limite,
    [string]$Cliente     = "",
    [string]$BackendUrl  = "http://localhost:5000",
    [string]$AppSettings = "C:\SigeDash\Backend\appsettings.Production.json"
)
$ErrorActionPreference = "Stop"

if ($Limite -lt 0) { Write-Error "Limite invalido (use 0 para ilimitado)."; exit 1 }
if (-not (Test-Path $AppSettings)) { Write-Error "appsettings nao encontrado: $AppSettings"; exit 1 }
$cfg = Get-Content $AppSettings -Raw | ConvertFrom-Json
$adminKey = $cfg.AdminKey
if ([string]::IsNullOrWhiteSpace($adminKey)) { Write-Error "AdminKey ausente no appsettings ($AppSettings)."; exit 1 }

$body = @{ limite = $Limite }
if ($Cliente) { $body["cliente"] = $Cliente }
$json = $body | ConvertTo-Json

try {
    $resp = Invoke-RestMethod -Uri "$BackendUrl/admin/limite-dispositivos" -Method POST `
        -Headers @{ "X-Admin-Key" = $adminKey; "Content-Type" = "application/json" } -Body $json
} catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    Write-Error "Falha ao definir o limite: $msg"
    exit 2
}

$lim = if ($resp.limiteDispositivos -gt 0) { $resp.limiteDispositivos } else { "ilimitado" }
$barra = "=" * 60
Write-Host ""
Write-Host $barra -ForegroundColor Green
Write-Host "  LIMITE DE DISPOSITIVOS ATUALIZADO:" -ForegroundColor Green
Write-Host "    Empresa          : $($resp.cliente)" -ForegroundColor White
Write-Host "    Limite           : $lim" -ForegroundColor Yellow
Write-Host "    Usuarios ativos  : $($resp.usuariosAtivos)" -ForegroundColor White
Write-Host $barra -ForegroundColor Green
Write-Host ""
