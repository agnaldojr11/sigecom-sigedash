<#
.SYNOPSIS
    Sincroniza um cliente JA INSTALADO com a SigeDash Central (liga a telemetria).
.DESCRIPTION
    Para clientes instalados ANTES do auto-registro (o auto-update nao re-roda o instalador).
    O suporte roda UMA vez na maquina do cliente, informando Nome e CNPJ. Registra na Central
    (idempotente - nao duplica) e liga a telemetria. Rode como Administrador.
.EXAMPLE
    .\sincronizar-central.ps1 -Nome "Ponto Verde" -Cnpj "45.177.977/0001-17"
#>
param(
    [Parameter(Mandatory)][string]$Nome,
    [string]$Cnpj       = "",
    [string]$BackendDir = "C:\SigeDash\Backend"
)

$ErrorActionPreference = "Stop"

# Precisa de admin (controla o servico do backend).
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

$reg = Join-Path $PSScriptRoot "registrar-central.ps1"
if (-not (Test-Path $reg)) { Write-Error "registrar-central.ps1 nao encontrado nesta pasta."; exit 1 }

Write-Host "Sincronizando '$Nome' com a SigeDash Central..." -ForegroundColor Cyan
& $reg -Nome $Nome -Cnpj $Cnpj -BackendDir $BackendDir -ScriptDir $PSScriptRoot
Write-Host "Concluido. Confira na Central (aba Frota) em ate ~3 min." -ForegroundColor Green
