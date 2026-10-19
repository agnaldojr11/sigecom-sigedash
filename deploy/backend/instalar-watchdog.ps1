<#
.SYNOPSIS
    Registra o Watchdog do SigeDash como tarefa agendada (SYSTEM): roda no inicio do Windows e a
    cada 5 minutos, garantindo que PostgreSQL + Backend + Tunnel fiquem no ar (corrige 502 Bad Gateway
    quando o backend nao sobe sozinho apos um reinicio).
.DESCRIPTION
    Pode ser rodado em QUALQUER cliente ja instalado (nao precisa reinstalar). Execute como Administrador.
.PARAMETER InstallDir
    Pasta do backend (onde esta/ira o watchdog). Padrao: C:\SigeDash\Backend
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\instalar-watchdog.ps1
#>
param(
    [string]$InstallDir = "C:\SigeDash\Backend"
)
$ErrorActionPreference = "Stop"
$TASK = "SigeDash-Watchdog"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute como Administrador."
    exit 1
}

# Garante o watchdog-sigedash.ps1 em $InstallDir (copia da pasta deste script, se preciso).
$wdDst = Join-Path $InstallDir "watchdog-sigedash.ps1"
$wdSrc = Join-Path $PSScriptRoot "watchdog-sigedash.ps1"
if ((Test-Path $wdSrc) -and ($wdSrc -ne $wdDst)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item $wdSrc $wdDst -Force
}
if (-not (Test-Path $wdDst)) { Write-Error "watchdog-sigedash.ps1 nao encontrado ($wdDst)."; exit 1 }

Write-Host "Registrando tarefa '$TASK' (inicio do Windows + a cada 5 min)..." -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName $TASK -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$wdDst`""

# Trigger 1: no inicio do Windows, com 1 min de folga para os servicos subirem.
$t1 = New-ScheduledTaskTrigger -AtStartup
try { $t1.Delay = "PT1M" } catch {}

# Trigger 2: repete a cada 5 min (duracao bem longa = efetivamente sempre).
$t2 = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(2)) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TASK `
    -Action   $action `
    -Trigger  $t1, $t2 `
    -Settings $settings `
    -RunLevel Highest `
    -User     "SYSTEM" `
    -Description "Watchdog: garante PostgreSQL+Backend+Tunnel no ar (boot + a cada 5 min)." | Out-Null

Write-Host "[OK] Tarefa '$TASK' registrada (SYSTEM, boot + a cada 5 min)." -ForegroundColor Green
Write-Host "     Log do watchdog: C:\SigeDash\watchdog.log" -ForegroundColor DarkGray

# Roda uma vez agora para ja deixar tudo no ar.
Write-Host "Rodando o watchdog agora..." -ForegroundColor Cyan
& powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File $wdDst
Write-Host "[OK] Watchdog executado. Veja C:\SigeDash\watchdog.log" -ForegroundColor Green
