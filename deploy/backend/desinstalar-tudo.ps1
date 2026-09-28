<#
.SYNOPSIS
    Remove COMPLETAMENTE o SigeDash deste servidor, para permitir uma reinstalacao limpa.
.DESCRIPTION
    Para e remove os servicos (backend, agente, tunnel), as tarefas agendadas, os arquivos e
    o banco 'sigedash'. Idempotente: nao falha se algo ja tiver sido removido.

    POR PADRAO preserva o servidor PostgreSQL (remove apenas o banco/usuario 'sigedash'), pois ele
    pode ter sido reaproveitado de outra instalacao. Use -RemoverPostgres para desinstalar o
    PostgreSQL inteiro (CUIDADO: apaga TODOS os bancos do PostgreSQL desta maquina).

    NAO mexe no Cloudflare (tunnel/DNS) nem na SigeDash Central - isso e gerenciado pela SistemasBr.
    Para reinstalar mantendo a MESMA URL, o instalador reaproveita o tunnel existente automaticamente.
    Para remover o cadastro na Central, use o painel da Central (detalhe do cliente -> Zona de perigo).
.PARAMETER RemoverPostgres
    Tambem desinstala o servidor PostgreSQL 16 e apaga a pasta de dados (destrutivo).
.PARAMETER PostgresSenha
    Senha do superusuario 'postgres' (para apagar o banco 'sigedash'). Se omitida, tenta sem senha
    (modo trust) e, se falhar, pergunta.
.PARAMETER Force
    Nao pede confirmacao (para uso nao-interativo).
.EXAMPLE
    .\desinstalar-tudo.ps1
    .\desinstalar-tudo.ps1 -Force
    .\desinstalar-tudo.ps1 -RemoverPostgres -Force
#>
param(
    [switch]$RemoverPostgres,
    [string]$PostgresSenha = "",
    [switch]$Force
)

# Nao aborta no meio: a limpeza deve seguir mesmo se um passo individual falhar.
$ErrorActionPreference = "Continue"

$LOG_FILE = Join-Path $env:TEMP ("sigedash-desinstalar-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$erros = 0

function Log($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content $LOG_FILE $line -Encoding UTF8 } catch {}
}
function Passo($msg) { Write-Host ""; Write-Host ">>> $msg" -ForegroundColor Cyan; Log ">>> $msg" }
function Ok($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green; Log "[OK] $msg" }
function Aviso($msg) { Write-Host "[--] $msg" -ForegroundColor Yellow; Log "[AVISO] $msg" }
function Erro($msg)  { $script:erros++; Write-Host "[ERRO] $msg" -ForegroundColor Red; Log "[ERRO] $msg" }

# --- Admin ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador (clique direito -> Executar como administrador)."
    exit 1
}

Write-Host ""
Write-Host ("=" * 62) -ForegroundColor Cyan
Write-Host "  SigeDash - DESINSTALACAO COMPLETA" -ForegroundColor Cyan
Write-Host ("=" * 62) -ForegroundColor Cyan
Write-Host "  Sera removido deste servidor:"
Write-Host "    - Servicos: SigeDashBackend, SigeDashAgente, cloudflared"
Write-Host "    - Tarefas agendadas: SigeDash-Atualizar, SigeDash-Aplicar"
Write-Host "    - Pastas: C:\SigeDash e C:\Program Files\SistemasBr\SigeDash"
Write-Host "    - Banco de dados 'sigedash' (usuario e base)"
if ($RemoverPostgres) {
    Write-Host "    - PostgreSQL 16 INTEIRO (todos os bancos!) -- -RemoverPostgres ativo" -ForegroundColor Red
} else {
    Write-Host "    - (o servidor PostgreSQL sera PRESERVADO; use -RemoverPostgres p/ remover tudo)"
}
Write-Host "  NAO sera tocado: Cloudflare (tunnel/DNS) e o cadastro na SigeDash Central."
Write-Host ("=" * 62) -ForegroundColor Cyan

if (-not $Force) {
    $c = Read-Host "  Confirma a desinstalacao completa? Digite SIM para prosseguir"
    if ($c -ne "SIM") { Write-Host "Cancelado."; exit 0 }
}

Log "=== Inicio da desinstalacao ==="

# --- 1) Servicos ---
function RemoverServico($nome) {
    $svc = Get-Service $nome -ErrorAction SilentlyContinue
    if (-not $svc) { Aviso "Servico '$nome' nao existe (ja removido)."; return }
    try {
        if ($svc.Status -ne "Stopped") { Stop-Service $nome -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
        & sc.exe delete $nome | Out-Null
        Start-Sleep -Seconds 1
        if (Get-Service $nome -ErrorAction SilentlyContinue) { Erro "Servico '$nome' ainda presente apos remocao (reinicie e tente de novo)." }
        else { Ok "Servico '$nome' removido." }
    } catch { Erro "Falha ao remover servico '$nome': $_" }
}

Passo "Parando e removendo servicos"
RemoverServico "SigeDashBackend"
RemoverServico "SigeDashAgente"
# cloudflared: usa o proprio uninstall antes do sc delete (limpa o registro do conector).
$cfExe = "C:\SigeDash\Tunnel\cloudflared.exe"
if (Test-Path $cfExe) {
    Stop-Service "cloudflared" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    & $cfExe service uninstall 2>&1 | Out-Null
}
RemoverServico "cloudflared"

# Chave de EventLog remanescente do cloudflared (o 'service uninstall' nao remove).
$evtKey = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared"
if (Test-Path $evtKey) {
    Remove-Item $evtKey -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $evtKey) { Aviso "Nao foi possivel remover a chave de EventLog do cloudflared." }
    else { Ok "Chave de EventLog do cloudflared removida." }
}

# --- 2) Tarefas agendadas ---
Passo "Removendo tarefas agendadas"
foreach ($t in @("SigeDash-Atualizar", "SigeDash-Aplicar")) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Erro "Tarefa '$t' nao removida." }
        else { Ok "Tarefa '$t' removida." }
    } else { Aviso "Tarefa '$t' nao existe (ja removida)." }
}

# --- 3) Banco de dados sigedash ---
Passo "Removendo o banco de dados 'sigedash'"
function DescobriPsql() {
    foreach ($v in @("17","16","15","14","13")) {
        $c = "C:\Program Files\PostgreSQL\$v\bin\psql.exe"
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
$psql = DescobriPsql
if (-not $psql) {
    Aviso "psql.exe nao encontrado - pulando remocao do banco (PostgreSQL pode ja ter sido removido)."
} else {
    # Descobre como conectar como postgres: 1) trust (sem senha), 2) senha informada, 3) pergunta.
    $senha = $PostgresSenha
    function TestaPg($s) {
        $env:PGPASSWORD = $s
        $out = & $psql -U postgres -d postgres -t -A -w -c "SELECT 1" 2>&1
        $env:PGPASSWORD = $null
        return (($out | Out-String).Trim() -match "^1")
    }
    $conecta = $false
    if (TestaPg "") { $senha = ""; $conecta = $true; Aviso "PostgreSQL em modo trust (sem senha)." }
    elseif (-not [string]::IsNullOrWhiteSpace($senha) -and (TestaPg $senha)) { $conecta = $true }
    elseif (-not $Force) {
        $ss = Read-Host -AsSecureString "  Senha do usuario 'postgres' (Enter para pular)"
        $senha = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
        if (-not [string]::IsNullOrWhiteSpace($senha) -and (TestaPg $senha)) { $conecta = $true }
    }

    if ($conecta) {
        $env:PGPASSWORD = $senha
        # WITH (FORCE) derruba conexoes remanescentes (PG13+).
        $d1 = & $psql -U postgres -d postgres -t -A -w -c "DROP DATABASE IF EXISTS sigedash WITH (FORCE);" 2>&1
        $d2 = & $psql -U postgres -d postgres -t -A -w -c "DROP USER IF EXISTS sigedash;" 2>&1
        $env:PGPASSWORD = $null
        Log "DROP DATABASE: $($d1 | Out-String)"; Log "DROP USER: $($d2 | Out-String)"
        Ok "Banco e usuario 'sigedash' removidos (se existiam)."
    } else {
        Aviso "Nao consegui conectar como 'postgres' - o banco 'sigedash' NAO foi removido. Remova manualmente se necessario."
    }
}

# --- 4) PostgreSQL inteiro (opcional) ---
if ($RemoverPostgres) {
    Passo "Desinstalando o PostgreSQL 16 (INTEIRO)"
    $pgDir = "C:\Program Files\PostgreSQL\16"
    $uninst = Join-Path $pgDir "uninstall-postgresql.exe"
    $svcPg = (Get-Service -Name "postgresql-x64-*" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($svcPg) { Stop-Service $svcPg.Name -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    if (Test-Path $uninst) {
        try {
            Start-Process -FilePath $uninst -ArgumentList "--mode unattended" -Wait
            Start-Sleep -Seconds 3
            Ok "PostgreSQL desinstalado."
        } catch { Erro "Falha ao desinstalar o PostgreSQL: $_" }
    } else { Aviso "Uninstaller do PostgreSQL nao encontrado em $uninst." }
    if (Test-Path $pgDir) {
        Remove-Item $pgDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $pgDir) { Aviso "Pasta '$pgDir' ainda presente (remova manualmente apos reiniciar)." }
        else { Ok "Pasta do PostgreSQL removida." }
    }
}

# --- 5) Pastas ---
Passo "Removendo arquivos"
# Preserva o log da desinstalacao (esta em %TEMP%, fora de C:\SigeDash).
foreach ($d in @("C:\Program Files\SistemasBr\SigeDash", "C:\SigeDash")) {
    if (Test-Path $d) {
        Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $d) { Erro "Nao foi possivel remover '$d' (arquivo em uso? reinicie e rode de novo)." }
        else { Ok "Pasta '$d' removida." }
    } else { Aviso "Pasta '$d' nao existe (ja removida)." }
}
# Remove a pasta pai SistemasBr se tiver ficado vazia.
$parent = "C:\Program Files\SistemasBr"
if ((Test-Path $parent) -and -not (Get-ChildItem $parent -Force -ErrorAction SilentlyContinue)) {
    Remove-Item $parent -Force -ErrorAction SilentlyContinue
}

# --- Resumo ---
Write-Host ""
Write-Host ("=" * 62) -ForegroundColor Cyan
if ($erros -eq 0) {
    Write-Host "  DESINSTALACAO CONCLUIDA - servidor limpo para reinstalar." -ForegroundColor Green
} else {
    Write-Host "  DESINSTALACAO CONCLUIDA COM $erros PENDENCIA(S)." -ForegroundColor Yellow
    Write-Host "  Reinicie o servidor e rode de novo para limpar o que ficou em uso." -ForegroundColor Yellow
}
Write-Host ("=" * 62) -ForegroundColor Cyan
Write-Host "  Log desta desinstalacao: $LOG_FILE"
Write-Host ""
Write-Host "  LEMBRETES:"
Write-Host "   - Cloudflare: o tunnel/DNS continua existindo (a reinstalacao reaproveita a mesma URL)."
Write-Host "   - SigeDash Central: para remover o cadastro de teste, use o painel (Zona de perigo)."
Write-Host "   - Reinstalar: rode o instalador de novo (ele detecta o tunnel existente e reutiliza)."
Write-Host ""
Log "=== Fim da desinstalacao (pendencias: $erros) ==="

if ($erros -gt 0) { exit 1 } else { exit 0 }
