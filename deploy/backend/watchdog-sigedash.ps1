<#
.SYNOPSIS
    Watchdog do SigeDash: garante PostgreSQL + Backend + Tunnel no ar e reinicia o backend
    se ele nao estiver respondendo. Pensado para rodar no boot e a cada poucos minutos.
.DESCRIPTION
    Cobre os casos que o auto-restart do servico sozinho NAO pega:
      - PostgreSQL demora no boot e o backend desiste de conectar (fica fora -> 502 Bad Gateway);
      - o servico SigeDashBackend fica "Running" mas o app travou/caiu internamente (nao responde);
      - algum servico nao voltou apos um reinicio da maquina.
    Registrado como tarefa agendada SYSTEM (ver instalar-watchdog.ps1): no inicio do Windows + a cada 5 min.
.PARAMETER BackendUrl
    URL local do backend. Padrao: http://localhost:5000
#>
param(
    [string]$BackendUrl = "http://localhost:5000"
)
$ErrorActionPreference = "Continue"
$LOG = "C:\SigeDash\watchdog.log"

function L($m) {
    $line = "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) $m"
    try { Add-Content -Path $LOG -Value $line -Encoding UTF8 } catch {}
}

# Mantem o log enxuto (ultimas ~500 linhas).
try {
    if ((Test-Path $LOG) -and (Get-Item $LOG).Length -gt 200KB) {
        $tail = Get-Content $LOG -Tail 500
        Set-Content -Path $LOG -Value $tail -Encoding UTF8
    }
} catch {}

function Garante($nome) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    if ($svc.Status -ne 'Running') {
        try { Start-Service $svc.Name -ErrorAction Stop; L "Servico '$($svc.Name)' estava $($svc.Status) -> iniciado." }
        catch { L "ERRO ao iniciar '$($svc.Name)': $_" }
    }
    return (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue)
}

# 1) PostgreSQL primeiro (o backend depende dele).
$pg = Get-Service -Name "postgresql-x64-*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pg) { Garante $pg.Name | Out-Null }

# 2) Backend: garante o servico rodando.
$bk = Garante "SigeDashBackend"
if ($bk -and $bk.Status -eq 'Running') { Start-Sleep -Seconds 5 }  # da um tempo pro app subir

# 3) Backend RESPONDE? (mesmo "Running" pode estar travado). Tenta algumas vezes.
$ok = $false
for ($i = 0; $i -lt 3; $i++) {
    try {
        $r = Invoke-WebRequest "$BackendUrl/auth/empresas" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch { }
    Start-Sleep -Seconds 5
}

if (-not $ok -and (Get-Service "SigeDashBackend" -ErrorAction SilentlyContinue)) {
    L "Backend NAO respondeu em $BackendUrl - reiniciando o servico."
    try {
        Restart-Service "SigeDashBackend" -Force -ErrorAction Stop
        Start-Sleep -Seconds 10
        try { $r2 = Invoke-WebRequest "$BackendUrl/auth/empresas" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
              if ($r2.StatusCode -eq 200) { L "Backend respondeu apos o restart." } }
        catch { L "AVISO: backend ainda nao respondeu apos o restart (ver Event Viewer / install.log)." }
    } catch { L "ERRO ao reiniciar o backend: $_" }
}

# 4) Tunnel (acesso externo).
Garante "cloudflared" | Out-Null
