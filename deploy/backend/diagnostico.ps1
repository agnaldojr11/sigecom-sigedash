<#
.SYNOPSIS
    Diagnostico do SigeDash - verifica cada componente e aponta a CAUSA e a SOLUCAO das falhas.
.DESCRIPTION
    Rode este script no servidor do cliente quando a instalacao falhar ou o acesso nao funcionar.
    Ele checa PostgreSQL, backend, agente, tunnel Cloudflare, Central e pre-requisitos, e gera um
    relatorio em C:\SigeDash\diagnostico-<data>.txt (envie ao suporte se precisar).
.PARAMETER FdbPath
    Caminho do banco Firebird do Sigecom. Padrao: C:\SIGECOM\SIGECOM.FDB
.PARAMETER Dominio
    Dominio raiz dos clientes (para montar a URL publica e testar o DNS/tunnel). Padrao: sigedash.com.br
#>
param(
    [string]$FdbPath = "C:\SIGECOM\SIGECOM.FDB",
    [string]$Dominio = "sigedash.com.br"
)

$ErrorActionPreference = "Continue"
$ok = 0; $falhas = 0; $avisos = 0
$linhas = New-Object System.Collections.Generic.List[string]

function Add($t) { $linhas.Add($t); Write-Host $t }
function Sec($t) { Add ""; Add ("== " + $t + " ==") }
function OK($m)    { $script:ok++;     Add ("  [OK]   " + $m) }
function FALHA($m, $sol) { $script:falhas++; Add ("  [FALHA] " + $m); if ($sol) { Add ("         -> " + $sol) } }
function AVISO($m, $sol) { $script:avisos++; Add ("  [AVISO] " + $m); if ($sol) { Add ("         -> " + $sol) } }
function INFO($m) { Add ("         " + $m) }

function TestaTCP($porta) {
    try { $t = New-Object System.Net.Sockets.TcpClient("localhost", $porta); $t.Close(); return $true } catch { return $false }
}
function DescobriPsql() {
    foreach ($v in @("17","16","15","14","13")) { $c = "C:\Program Files\PostgreSQL\$v\bin\psql.exe"; if (Test-Path $c) { return $c } }
    $cmd = Get-Command psql.exe -ErrorAction SilentlyContinue; if ($cmd) { return $cmd.Source }; return $null
}

$agora = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add ("=" * 64)
Add "  SigeDash - DIAGNOSTICO"
Add ("  " + $agora + "  |  " + $env:COMPUTERNAME)
Add ("=" * 64)

# --- Admin ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Sec "Pre-requisitos"
if ($isAdmin) { OK "Executando como Administrador." }
else { AVISO "NAO esta como Administrador." "Alguns testes podem falhar. Rode o PowerShell como Administrador." }

# --- Visual C++ Redistributable (necessario para o PostgreSQL inicializar) ---
$vc = $false
try {
    $r = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
    if ($r -and $r.Installed -eq 1) { $vc = $true }
} catch {}
if ($vc) { OK "Visual C++ Redistributable x64 presente." }
else { AVISO "Visual C++ Redistributable x64 nao detectado." "Sem ele o PostgreSQL nao inicializa. Instale o vc_redist.x64 (o instalador do SigeDash ja pede --install_runtimes 1)." }

# --- Espaco em disco ---
try {
    $c = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($c) {
        $freeGb = [math]::Round($c.Free / 1GB, 1)
        if ($freeGb -lt 2) { AVISO "Pouco espaco livre em C: ($freeGb GB)." "Libere espaco - a instalacao do PostgreSQL/backend pode falhar." }
        else { OK "Espaco livre em C: $freeGb GB." }
    }
} catch {}

# .NET Framework 4.8 (necessario para o AGENTE; o backend e self-contained e nao precisa de runtime).
try {
    $ndp = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop
    if ([int]$ndp.Release -ge 528040) { OK ".NET Framework 4.8 presente (Release $($ndp.Release))." }
    else { AVISO ".NET Framework 4.8 ausente (Release $($ndp.Release))." "O agente nao inicia sem 4.8. Instale: dotnet.microsoft.com/download/dotnet-framework/net48" }
} catch {
    AVISO "Nao foi possivel confirmar o .NET Framework 4.8." "Se o servico SigeDashAgente nao iniciar, instale o .NET Framework 4.8." }

# --- PostgreSQL ---
Sec "PostgreSQL"
$svcPg = Get-Service | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
$porta5432 = TestaTCP 5432
$psql = DescobriPsql
if ($svcPg) {
    if ($svcPg.Status -eq "Running") { OK "Servico $($svcPg.Name) rodando." }
    else { FALHA "Servico $($svcPg.Name) existe mas esta $($svcPg.Status)." "Inicie: Start-Service $($svcPg.Name)" }
} else { FALHA "Nenhum servico PostgreSQL encontrado." "O PostgreSQL nao foi instalado. Rode instalar-postgres.ps1 ou o instalador completo." }
if ($porta5432) { OK "Porta 5432 respondendo." } else { FALHA "Porta 5432 nao responde." "O PostgreSQL nao esta ouvindo. Verifique o servico e o postgresql.conf (listen_addresses)." }
if ($psql) { OK "psql.exe: $psql" } else { AVISO "psql.exe nao encontrado." "PostgreSQL pode estar ausente ou fora do PATH." }

if ($psql -and $porta5432) {
    $env:PGPASSWORD = ""
    $trust = & $psql -U postgres -d postgres -t -A -w -c "SELECT 1" 2>&1
    $env:PGPASSWORD = $null
    if (($trust | Out-String).Trim() -match "^1") {
        AVISO "PostgreSQL aceita conexao SEM SENHA (modo trust)." "Recomendado ajustar pg_hba.conf para scram-sha-256 nas conexoes locais."
    }
    # Existe o banco/usuario sigedash? (via superusuario em trust; senao so informa)
    if (($trust | Out-String).Trim() -match "^1") {
        $env:PGPASSWORD = ""
        $dbTest = & $psql -U postgres -d postgres -t -A -w -c "SELECT 1 FROM pg_database WHERE datname='sigedash'" 2>&1
        $env:PGPASSWORD = $null
        if (($dbTest | Out-String).Trim() -match "^1") { OK "Banco 'sigedash' existe." }
        else { FALHA "Banco 'sigedash' NAO existe." "Rode instalar-postgres.ps1 (ou o instalador completo)." }
    } else {
        INFO "Banco 'sigedash': nao verificado (postgres exige senha)."
    }
}

# --- Backend ---
Sec "Backend (SigeDashBackend)"
$appDir = "C:\SigeDash\Backend"
$svcBk = Get-Service "SigeDashBackend" -ErrorAction SilentlyContinue
$appJson = Join-Path $appDir "appsettings.Production.json"
if (Test-Path $appJson -ErrorAction SilentlyContinue) {
    OK "appsettings.Production.json presente."
    try { Get-Content $appJson -Raw | ConvertFrom-Json | Out-Null; OK "appsettings.Production.json e um JSON valido." }
    catch { FALHA "appsettings.Production.json invalido (JSON quebrado)." "Reinstale o backend ou corrija o arquivo." }
} else { FALHA "appsettings.Production.json ausente em $appDir." "O backend nao foi instalado. Rode instalar-backend.ps1 (ou o instalador completo)." }

if ($svcBk) {
    if ($svcBk.Status -eq "Running") { OK "Servico SigeDashBackend rodando." }
    else {
        FALHA "Servico SigeDashBackend esta $($svcBk.Status)." "Tente Start-Service SigeDashBackend. Se cair, veja o erro abaixo."
        # Ultimo erro do .NET no Event Log
        $evt = Get-EventLog -LogName Application -Newest 40 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "SigeDash|SigeDash.Api|\.NET Runtime" } | Select-Object -First 1
        if ($evt) { INFO ("Event Log: " + (($evt.Message -split "`n")[0])) }
    }
} else { FALHA "Servico SigeDashBackend nao existe." "O backend nao foi instalado. Rode instalar-backend.ps1 (ou o instalador completo)." }

if (TestaTCP 5000) {
    OK "Porta 5000 respondendo."
    try {
        $h = Invoke-WebRequest "http://localhost:5000/health" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        OK "Backend /health OK (HTTP $($h.StatusCode))."
    } catch {
        # /health pode nao existir em versoes antigas; tenta /auth/empresas
        try { $h2 = Invoke-WebRequest "http://localhost:5000/auth/empresas" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop; OK "Backend respondendo (/auth/empresas HTTP $($h2.StatusCode))." }
        catch { AVISO "Porta 5000 aberta mas o backend nao respondeu ao teste HTTP." "Aguarde alguns segundos; se persistir, veja o Event Viewer." }
    }
} else { FALHA "Porta 5000 nao responde." "O backend nao esta no ar. Verifique o servico e o Event Viewer." }

# --- Agente ---
Sec "Agente (SigeDashAgente)"
$svcAg = Get-Service "SigeDashAgente" -ErrorAction SilentlyContinue
$agCfg = "C:\Program Files\SistemasBr\SigeDash\Config\agente.config.json"
if ($svcAg) {
    if ($svcAg.Status -eq "Running") { OK "Servico SigeDashAgente rodando." }
    else { FALHA "Servico SigeDashAgente esta $($svcAg.Status)." "Tente Start-Service SigeDashAgente e veja o Event Viewer." }
} else { AVISO "Servico SigeDashAgente nao existe." "O agente pode nao ter sido instalado. Rode instalar-agente.ps1." }
if (Test-Path $agCfg -ErrorAction SilentlyContinue) { OK "agente.config.json presente." }
else { AVISO "agente.config.json ausente." "O agente nao foi configurado (configurar-cliente.ps1)." }

# --- Firebird (fonte de dados do agente) ---
Sec "Firebird / SIGECOM"
if (Test-Path $FdbPath) {
    OK "Banco Firebird encontrado: $FdbPath"
    $isqlCands = @(
        "C:\Program Files\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files\Firebird\Firebird_3_0\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_3_0\bin\isql.exe"
    )
    $isql = $isqlCands | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($isql) {
        $sqlFile = Join-Path $env:TEMP "sigedash_diag.sql"
        @("SELECT 1 FROM RDB`$DATABASE;", "EXIT;") | Out-File $sqlFile -Encoding ASCII
        $out = & $isql -user SYSDBA -password masterkey $FdbPath -q -i $sqlFile 2>&1
        Remove-Item $sqlFile -ErrorAction SilentlyContinue
        if (($out | Out-String) -match "1") { OK "Conexao ao Firebird OK (SYSDBA)." }
        else { AVISO "Nao consegui consultar o Firebird." ("Detalhe: " + (($out | Out-String).Trim())) }
    } else { AVISO "isql.exe do Firebird nao encontrado." "Instale/verifique o Firebird do SIGECOM." }
} else { AVISO "Banco Firebird nao encontrado em $FdbPath." "Confirme o caminho do .FDB (parametro -FdbPath)." }

# --- Cloudflare Tunnel ---
Sec "Cloudflare Tunnel (acesso externo)"
$svcCf = Get-Service "cloudflared" -ErrorAction SilentlyContinue
if ($svcCf) {
    if ($svcCf.Status -eq "Running") { OK "Servico cloudflared rodando." }
    else { FALHA "Servico cloudflared esta $($svcCf.Status)." "Sem ele o cliente nao acessa de fora. Veja tunnel-install.log e o token." }
} else { AVISO "Servico cloudflared nao existe." "O tunnel nao foi instalado (o acesso externo nao funciona ate configurar)." }
$cfLog = "C:\SigeDash\Tunnel\tunnel-install.log"
if (Test-Path $cfLog -ErrorAction SilentlyContinue) {
    $ultimas = Get-Content $cfLog -Tail 3 -ErrorAction SilentlyContinue
    if ($ultimas) { INFO "Ultimas linhas do tunnel-install.log:"; $ultimas | ForEach-Object { INFO ("   " + $_) } }
}

# --- URL publica (DNS + acesso externo de ponta a ponta) ---
# Deriva o slug do nome da empresa (mesmo algoritmo do instalador) e testa a URL publica.
# Pega o DNS NAO criado (ERR_NAME_NOT_RESOLVED no cliente) e o tunnel fora (Error 1033).
Sec "URL publica (DNS + tunnel ponta-a-ponta)"
$nomeEmp = $null
try {
    $emp = Invoke-RestMethod "http://localhost:5000/auth/empresas" -TimeoutSec 8
    $nomeEmp = ($emp | Select-Object -First 1).nome
} catch {}
if ([string]::IsNullOrWhiteSpace($nomeEmp)) {
    AVISO "Nao foi possivel obter a empresa para montar a URL publica." "Resolva os itens do Backend/empresa acima primeiro."
} else {
    $slug = ($nomeEmp -replace '[^a-zA-Z0-9]', '').ToLower()
    if ($slug.Length -gt 20) { $slug = $slug.Substring(0, 20) }
    $hostPub = "$slug.$Dominio"
    $urlPub  = "https://$hostPub"
    INFO "URL publica esperada: $urlPub"
    # 1) DNS resolve?
    $resolve = $false
    try { [System.Net.Dns]::GetHostEntry($hostPub) | Out-Null; $resolve = $true } catch { $resolve = $false }
    if (-not $resolve) {
        FALHA "O DNS de $hostPub NAO resolve (registro nao existe)." "No celular isso aparece como ERR_NAME_NOT_RESOLVED. Crie o 'Public Hostname'/DNS do tunnel no painel Cloudflare (ou reinstale com auto-criacao do tunnel: deixe o token em branco). Confira tambem se o nome do cliente bate com o slug."
    } else {
        OK "DNS de $hostPub resolve."
        # 2) Responde de fora (via Cloudflare)?
        try {
            $hp = Invoke-WebRequest "$urlPub/health" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            OK "URL publica respondeu (HTTP $($hp.StatusCode)) - acesso externo OK."
        } catch {
            FALHA "O DNS resolve mas $urlPub NAO respondeu (provavel tunnel fora - Cloudflare Error 1033)." "Verifique o servico cloudflared (rodando?) e o token do tunnel; veja tunnel-install.log."
        }
    }
    INFO "ATENCAO: use a URL COM '$Dominio' (nao esqueca o '.br' se for .com.br)."
}

# --- Central ---
Sec "SigeDash Central (telemetria)"
$centralJson = Join-Path $appDir "central.json"
$centralNoScript = Join-Path $PSScriptRoot "central.json"
$cj = if (Test-Path $centralJson -ErrorAction SilentlyContinue) { $centralJson } elseif (Test-Path $centralNoScript -ErrorAction SilentlyContinue) { $centralNoScript } else { $null }
# A Url da Central fica no appsettings (bloco Central) apos o registro.
$urlCentral = $null
if (Test-Path $appJson -ErrorAction SilentlyContinue) {
    try { $j = Get-Content $appJson -Raw | ConvertFrom-Json; if ($j.Central -and $j.Central.Url) { $urlCentral = $j.Central.Url } } catch {}
}
if ($urlCentral) {
    OK "Bloco Central configurado no appsettings (Url: $urlCentral)."
    try { $hc = Invoke-WebRequest ($urlCentral.TrimEnd('/') + "/health") -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop; OK "Central acessivel (HTTP $($hc.StatusCode))." }
    catch { AVISO "Nao consegui acessar a Central em $urlCentral." "Verifique a internet do servidor; a telemetria e fail-open (nao bloqueia o cliente)." }
} elseif ($cj) {
    AVISO "central.json presente mas o backend ainda nao registrou (sem bloco Central no appsettings)." "Rode registrar-central.ps1 -Nome '<cliente>' -Cnpj '<cnpj>'."
} else {
    AVISO "Sem central.json - telemetria nao configurada." "Adicione o central.json ao pacote se quiser o cliente na Central."
}

# --- Resumo ---
Add ""
Add ("=" * 64)
Add ("  RESUMO:  OK=$ok   FALHA=$falhas   AVISO=$avisos")
if ($falhas -eq 0) { Add "  Nenhuma falha critica detectada." }
else { Add "  Resolva os itens [FALHA] acima (a linha '->' diz como)." }
Add ("=" * 64)

# --- Grava o relatorio ---
$destDir = "C:\SigeDash"
try { New-Item -ItemType Directory -Path $destDir -Force | Out-Null } catch {}
$rel = Join-Path $destDir ("diagnostico-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
try {
    $linhas | Out-File $rel -Encoding UTF8
    Write-Host ""
    Write-Host ("Relatorio salvo em: " + $rel) -ForegroundColor Cyan
    Write-Host "Envie este arquivo ao suporte se precisar de ajuda." -ForegroundColor Cyan
} catch { Write-Host "AVISO: nao consegui salvar o relatorio em $rel" -ForegroundColor Yellow }

if ($falhas -gt 0) { exit 1 } else { exit 0 }
