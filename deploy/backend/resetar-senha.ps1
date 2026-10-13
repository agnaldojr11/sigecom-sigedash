<#
.SYNOPSIS
    Redefine a senha de um usuario do SigeDash NA PROPRIA MAQUINA do cliente (recuperacao).
.DESCRIPTION
    Use quando o ADM (ou qualquer usuario) perdeu a senha e nao ha outro admin para reseta-lo
    pela tela. Roda LOCALMENTE no servidor do cliente: le a AdminKey do appsettings e chama o
    endpoint local /admin/reset-senha (bloqueado para acesso externo). Gera uma senha temporaria
    (troca obrigatoria no proximo login) e derruba a sessao ativa do usuario.

    Execute como Administrador, no servidor onde o SigeDash Backend esta instalado.
    Para um atalho clicavel, use o Resetar-Senha.cmd (auto-eleva e pergunta o login).
.PARAMETER Login
    Login do usuario a resetar. Se vazio e rodando interativo, pergunta (Enter = admin).
.PARAMETER Cliente
    Nome da empresa. Opcional se houver apenas 1 cliente (caso normal no servidor do cliente).
.PARAMETER BackendUrl
    URL local do backend. Padrao: http://localhost:5000
.PARAMETER AppSettings
    Caminho do appsettings.Production.json (de onde a AdminKey e lida).
.EXAMPLE
    .\resetar-senha.ps1
    .\resetar-senha.ps1 -Login gerente
    .\resetar-senha.ps1 -Login admin -Cliente "SBR Implementacao"
#>
param(
    [string]$Login       = "",
    [string]$Cliente     = "",
    [string]$BackendUrl  = "http://localhost:5000",
    [string]$AppSettings = "C:\SigeDash\Backend\appsettings.Production.json"
)
$ErrorActionPreference = "Stop"

# TLS 1.2 (Windows Server antigo) - defesa, embora aqui seja localhost.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

if (-not (Test-Path $AppSettings)) {
    Write-Host "[ERRO] appsettings nao encontrado: $AppSettings" -ForegroundColor Red
    Write-Host "       Rode este script no SERVIDOR onde o SigeDash Backend esta instalado." -ForegroundColor Yellow
    exit 1
}
$cfg = Get-Content $AppSettings -Raw | ConvertFrom-Json
$adminKey = $cfg.AdminKey
if ([string]::IsNullOrWhiteSpace($adminKey)) { Write-Host "[ERRO] AdminKey ausente no appsettings ($AppSettings)." -ForegroundColor Red; exit 1 }

# Backend no ar?
try { Invoke-RestMethod "$BackendUrl/auth/empresas" -TimeoutSec 8 | Out-Null }
catch {
    Write-Host "[ERRO] O backend nao respondeu em $BackendUrl." -ForegroundColor Red
    Write-Host "       Verifique o servico 'SigeDashBackend' (services.msc) ou rode diagnostico.ps1." -ForegroundColor Yellow
    exit 1
}

# Login: pergunta se nao veio por parametro e estamos num console interativo.
if ([string]::IsNullOrWhiteSpace($Login)) {
    if ([Environment]::UserInteractive) {
        $inp   = Read-Host "Login do usuario a resetar (Enter = admin)"
        $Login = if ([string]::IsNullOrWhiteSpace($inp)) { "admin" } else { $inp.Trim() }
    } else { $Login = "admin" }
}

function Resetar($loginAlvo, $empresa) {
    $body = @{ login = $loginAlvo }
    if ($empresa) { $body["cliente"] = $empresa }
    $json = $body | ConvertTo-Json -Compress
    # UTF-8 explicito (nomes com acento quebram com 400 no PowerShell 5.1 - envia Latin1).
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Uri "$BackendUrl/admin/reset-senha" -Method POST `
        -Headers @{ "X-Admin-Key" = $adminKey } -ContentType "application/json; charset=utf-8" -Body $bytes
}

Write-Host "Resetando a senha de '$Login'..." -ForegroundColor Cyan
try {
    $resp = Resetar $Login $Cliente
} catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }

    # Mais de um cliente no servidor: pergunta a empresa e tenta de novo (so no modo interativo).
    if ($msg -match "mais de um cliente" -and [Environment]::UserInteractive -and -not $Cliente) {
        $empresa = Read-Host "Ha mais de uma empresa neste servidor. Informe o nome exato da empresa"
        try { $resp = Resetar $Login $empresa }
        catch {
            $m2 = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $m2 = $_.ErrorDetails.Message }
            Write-Host "[ERRO] Falha ao resetar a senha: $m2" -ForegroundColor Red; exit 2
        }
    } else {
        Write-Host "[ERRO] Falha ao resetar a senha: $msg" -ForegroundColor Red
        if ($msg -match "nao encontrado") { Write-Host "       Confira o login (ex.: admin) e tente de novo." -ForegroundColor Yellow }
        exit 2
    }
}

$barra = "=" * 60
Write-Host ""
Write-Host $barra -ForegroundColor Green
Write-Host "  SENHA REDEFINIDA - entregue ao usuario:" -ForegroundColor Green
Write-Host "    Empresa : $($resp.cliente)" -ForegroundColor White
Write-Host "    Login   : $($resp.login)" -ForegroundColor White
Write-Host "    Senha   : $($resp.senhaTemporaria)" -ForegroundColor Yellow
Write-Host "  (a troca de senha e OBRIGATORIA no proximo login; a sessao atual foi encerrada)" -ForegroundColor DarkYellow
Write-Host $barra -ForegroundColor Green
Write-Host ""
