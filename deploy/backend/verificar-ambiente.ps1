<#
.SYNOPSIS
    Pre-verificacao do servidor ANTES de instalar o SigeDash.
.DESCRIPTION
    Confere de uma vez TODOS os requisitos que ja derrubaram instalacoes em campo e lista cada
    problema com a causa e a solucao - antes de qualquer alteracao no servidor. Assim a instalacao
    nao para no meio com "um erro diferente a cada tentativa".

    Niveis:
      [OK]       requisito atendido
      [INFO]     situacao conhecida que o instalador trata sozinho (ex.: reinstalacao)
      [AVISO]    nao impede a instalacao, mas algo pode nao funcionar 100%
      [BLOQUEIO] a instalacao NAO vai funcionar ate resolver (o instalador nem comeca)

    Correcoes automaticas SEGURAS (desligue com -SemCorrecoes):
      - desbloqueia os arquivos do pacote baixado da internet (Unblock-File)
      - inicia o servico do Firebird se estiver parado
      - habilita o TLS 1.2 no Windows quando o HTTPS falha por "canal seguro" (exige reiniciar)

    Saida: exit 0 = pode instalar; exit 2 = ha BLOQUEIOS.
    Resultado gravado em C:\SigeDash\preverificacao.json (vai no relatorio enviado a Central).
.PARAMETER FdbPath
    Caminho do banco do SIGECOM. Padrao: C:\SIGECOM\SIGECOM.FDB
.PARAMETER ScriptDir
    Pasta do pacote de instalacao. Padrao: a pasta deste script.
.PARAMETER TunnelManual
    O token do tunnel foi informado manualmente (nao usa a API do Cloudflare do pacote).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verificar-ambiente.ps1
    powershell -ExecutionPolicy Bypass -File .\verificar-ambiente.ps1 -FdbPath "D:\SIGECOM\SIGECOM.FDB"
#>
param(
    [string]$FdbPath   = "C:\SIGECOM\SIGECOM.FDB",
    [string]$ScriptDir = $PSScriptRoot,
    [switch]$TunnelManual,
    [switch]$SemCorrecoes
)

$ErrorActionPreference = "Continue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13 } catch {}

# Mesmos valores fixados nos scripts de instalacao (manter em sincronia).
$PG_URL       = "https://get.enterprisedb.com/postgresql/postgresql-16.9-1-windows-x64.exe"
$PG_DIR       = "C:\Program Files\PostgreSQL\16"
$SAIDA_JSON   = "C:\SigeDash\preverificacao.json"

$itens = New-Object System.Collections.ArrayList
$script:reiniciar = $false

function Resultado($nivel, $titulo, $detalhe, $solucao) {
    [void]$itens.Add([ordered]@{ nivel = $nivel; titulo = $titulo; detalhe = "$detalhe"; solucao = "$solucao" })
    $cor = @{ OK = "Green"; INFO = "Gray"; AVISO = "Yellow"; BLOQUEIO = "Red" }[$nivel]
    $linha = "[{0}] {1}" -f $nivel, $titulo
    if ($detalhe) { $linha += " - $detalhe" }
    Write-Host $linha -ForegroundColor $cor
    if ($solucao -and $nivel -ne "OK") { Write-Host "      -> $solucao" -ForegroundColor $cor }
}

function TestaTcp($hostAlvo, $porta, $timeoutMs) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($hostAlvo, $porta, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) { return $false }
        $c.EndConnect($ar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

# Processo que esta ESCUTANDO na porta local (nome ou $null). Get-NetTCPConnection existe a partir
# do 2012; netstat e o fallback.
function DonoDaPorta($porta) {
    $procId = $null
    try {
        $con = Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($con) { $procId = $con.OwningProcess }
    } catch {
        $l = & netstat -ano -p TCP 2>$null | Where-Object { $_ -match "^\s*TCP\s+\S+:$porta\s+\S+\s+LISTENING\s+(\d+)" } | Select-Object -First 1
        if ($l -and $l -match "LISTENING\s+(\d+)") { $procId = [int]$Matches[1] }
    }
    if (-not $procId) { return $null }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($p) { return "$($p.ProcessName) (PID $procId)" } else { return "PID $procId" }
}

# HTTPS sem baixar o corpo. Qualquer resposta HTTP (inclusive 4xx) = o servidor alcanca o host.
function TestaHttps($url, $metodo) {
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
        $req.Method = $metodo
        $req.Timeout = 20000
        $req.AllowAutoRedirect = $false
        $req.UserAgent = "SigeDash-Preverificacao"
        $resp = $req.GetResponse()
        $r = @{ Ok = $true; Codigo = [int]$resp.StatusCode; Data = $resp.Headers["Date"] }
        $resp.Close()
        return $r
    } catch [System.Net.WebException] {
        $e = $_.Exception
        if ($e.Response) {
            $codigo = [int]$e.Response.StatusCode
            $data = $e.Response.Headers["Date"]
            $e.Response.Close()
            if ($codigo -eq 407) { return @{ Ok = $false; Status = "Proxy407"; Msg = "o proxy da rede exige autenticacao" } }
            return @{ Ok = $true; Codigo = $codigo; Data = $data }
        }
        return @{ Ok = $false; Status = "$($e.Status)"; Msg = $e.Message }
    } catch {
        return @{ Ok = $false; Status = "Outro"; Msg = $_.Exception.Message }
    }
}

# Traduz a falha de HTTPS em causa + solucao (e aplica o TLS 1.2 quando for o caso).
$script:tlsCorrigido = $false
function FalhaRede($nivel, $nomeHost, $uso, $r) {
    $st = "" + $r.Status
    if ($st -eq "SecureChannelFailure" -or $r.Msg -match "SSL/TLS|canal seguro|secure channel") {
        if (-not $SemCorrecoes -and -not $script:tlsCorrigido) { HabilitarTls12; $script:tlsCorrigido = $true }
        if ($script:tlsCorrigido) {
            Resultado "BLOQUEIO" "HTTPS para $nomeHost ($uso)" "falha de canal seguro (TLS 1.2 desligado no Windows)" "O TLS 1.2 foi habilitado agora. REINICIE o servidor e rode o instalador de novo."
            $script:reiniciar = $true
        } else {
            Resultado "BLOQUEIO" "HTTPS para $nomeHost ($uso)" "falha de canal seguro (TLS 1.2 desligado no Windows)" "Rode habilitar-tls12.ps1 como Administrador, reinicie o servidor e rode o instalador de novo."
        }
    } elseif ($st -eq "TrustFailure") {
        Resultado $nivel "HTTPS para $nomeHost ($uso)" "certificado nao confiavel (certificados raiz do Windows desatualizados ou inspecao HTTPS do antivirus/firewall)" "Rode o Windows Update (atualizacao de certificados raiz) ou libere $nomeHost da inspecao HTTPS do firewall/antivirus."
    } elseif ($st -eq "NameResolutionFailure") {
        Resultado $nivel "HTTPS para $nomeHost ($uso)" "o nome nao resolve (sem DNS/internet)" "Confira a internet e o DNS do servidor (teste abrir https://$nomeHost no navegador do servidor)."
    } elseif ($st -eq "Proxy407" -or $st -eq "ProxyNameResolutionFailure") {
        Resultado $nivel "HTTPS para $nomeHost ($uso)" $r.Msg "Libere este servidor no proxy da rede (saida direta, sem autenticacao) para $nomeHost."
    } else {
        Resultado $nivel "HTTPS para $nomeHost ($uso)" ("sem resposta (" + $(if ($st) { $st } else { "erro" }) + ")") "Firewall/proxy bloqueando a saida TCP 443 para $nomeHost. Libere a saida HTTPS para esse endereco."
    }
}

function HabilitarTls12() {
    try {
        foreach ($k in @("HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319")) {
            if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
            New-ItemProperty -Path $k -Name "SchUseStrongCrypto" -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $k -Name "SystemDefaultTlsVersions" -Value 1 -PropertyType DWord -Force | Out-Null
        }
        $base = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2"
        foreach ($lado in @("Client", "Server")) {
            if (-not (Test-Path "$base\$lado")) { New-Item -Path "$base\$lado" -Force | Out-Null }
            New-ItemProperty -Path "$base\$lado" -Name "Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path "$base\$lado" -Name "DisabledByDefault" -Value 0 -PropertyType DWord -Force | Out-Null
        }
    } catch { Write-Host "AVISO: nao consegui habilitar o TLS 1.2 automaticamente: $_" -ForegroundColor Yellow }
}

# isql.exe do Firebird: primeiro pela pasta do servico instalado (qualquer versao/caminho), depois
# pelos caminhos padrao.
function LocalizarIsql() {
    $svcs = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -match 'fbserver|fb_inet_server|fb_smp_server|fbguard|firebird\.exe' }
    foreach ($s in $svcs) {
        if ($s.PathName -match '^"?([^"]+\\)[^\\"]+\.exe') {
            $dir = $Matches[1]
            foreach ($c in @((Join-Path $dir "isql.exe"), (Join-Path $dir "bin\isql.exe"))) {
                if (Test-Path -LiteralPath $c) { return $c }
            }
        }
    }
    foreach ($c in @(
        "C:\Program Files\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files\Firebird\Firebird_3_0\isql.exe",
        "C:\Program Files\Firebird\Firebird_3_0\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_3_0\isql.exe",
        "C:\Program Files\Firebird\Firebird_4_0\isql.exe",
        "C:\Program Files\Firebird\Firebird_5_0\isql.exe")) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

Write-Host ""
Write-Host ("=" * 64) -ForegroundColor Cyan
Write-Host "  SigeDash - Pre-verificacao do servidor" -ForegroundColor Cyan
Write-Host ("=" * 64) -ForegroundColor Cyan

# ---------------------------------------------------------------- Sistema
$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($ehAdmin) { Resultado "OK" "Executando como Administrador" }
else { Resultado "BLOQUEIO" "Sem privilegio de Administrador" "" "Clique com o botao direito no instalador -> Executar como administrador." }

$os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
$osNome = if ($os) { "$($os.Caption) (build $($os.BuildNumber))" } else { "desconhecido" }
$build = if ($os) { [int]$os.BuildNumber } else { 0 }
if (-not [Environment]::Is64BitOperatingSystem) {
    Resultado "BLOQUEIO" "Windows 32 bits" $osNome "O SigeDash exige Windows 64 bits."
} elseif ($build -gt 0 -and $build -lt 9200) {
    Resultado "BLOQUEIO" "Windows nao suportado" $osNome "Minimo: Windows Server 2012 R2 / Windows 8.1 (64 bits)."
} elseif ($build -gt 0 -and $build -lt 9600) {
    Resultado "AVISO" "Windows Server 2012 (nao R2)" $osNome "Nao homologado para o PostgreSQL 16. Se o PASSO 1 falhar, use um servidor 2012 R2 ou superior."
} else {
    Resultado "OK" "Sistema operacional" $osNome
}

$psv = $PSVersionTable.PSVersion
if ($psv.Major -lt 3) { Resultado "BLOQUEIO" "PowerShell $psv" "" "Instale o Windows Management Framework 5.1 (PowerShell 5.1) e reinicie." }
else { Resultado "OK" "PowerShell $psv" }

try {
    $rel = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop).Release
} catch { $rel = 0 }
if ($rel -ge 528040) { Resultado "OK" ".NET Framework 4.8" }
else {
    Resultado "BLOQUEIO" ".NET Framework 4.8 ausente" "Release=$rel" "Sem ele o AGENTE nao inicia e os dados nunca sincronizam. Instale o .NET Framework 4.8 (https://dotnet.microsoft.com/download/dotnet-framework/net48), reinicie e rode o instalador de novo."
}

$disco = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
if ($disco) {
    $livreGb = [math]::Round($disco.FreeSpace / 1GB, 1)
    if ($livreGb -lt 1.5) { Resultado "BLOQUEIO" "Pouco espaco no disco C:" "$livreGb GB livres" "Libere pelo menos 3 GB no disco C: (PostgreSQL + SigeDash)." }
    elseif ($livreGb -lt 3) { Resultado "AVISO" "Espaco no disco C: baixo" "$livreGb GB livres" "Recomendado: 3 GB ou mais." }
    else { Resultado "OK" "Espaco no disco C:" "$livreGb GB livres" }
}

$rebootPendente = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or
                  (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
if ($rebootPendente) { Resultado "AVISO" "Windows com reinicio pendente (atualizacoes)" "" "Se der para reiniciar antes, reinicie: instaladores (VC++/PostgreSQL) costumam falhar com reinicio pendente." }

# ---------------------------------------------------------------- Pacote
$pastaPacote = "" + $ScriptDir
if ($pastaPacote -match '\\AppData\\Local\\Temp\\' -and $pastaPacote -match '\.zip|Rar\$|7z') {
    Resultado "BLOQUEIO" "Instalador rodando de DENTRO do .zip" $pastaPacote "Extraia o .zip inteiro para uma pasta (ex.: C:\SigeDash-Instalador) e rode o instalador de la."
}
$obrigatorios = @("version.txt", "SigeDash.Api.exe", "agente\SigeDash.Agente.exe", "instalar-postgres.ps1",
                  "instalar-backend.ps1", "instalar-agente.ps1", "instalar-tunnel.ps1", "configurar-cliente.ps1")
$faltando = @($obrigatorios | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pastaPacote $_)) })
if ($faltando.Count -gt 0) {
    Resultado "BLOQUEIO" "Pacote de instalacao incompleto" ("faltam: " + ($faltando -join ", ")) "Extraia o .zip INTEIRO de novo (nao copie arquivos soltos) ou baixe o pacote de novo pela Central."
} else {
    $versaoPacote = (Get-Content -LiteralPath (Join-Path $pastaPacote "version.txt") -ErrorAction SilentlyContinue | Select-Object -First 1)
    $corrompido = @()
    foreach ($exe in @("SigeDash.Api.exe", "agente\SigeDash.Agente.exe")) {
        $sig = Get-AuthenticodeSignature -LiteralPath (Join-Path $pastaPacote $exe) -ErrorAction SilentlyContinue
        if ($sig -and ($sig.Status -eq "HashMismatch" -or $sig.Status -eq "NotSigned")) { $corrompido += "$exe ($($sig.Status))" }
    }
    if ($corrompido.Count -gt 0) { Resultado "BLOQUEIO" "Arquivos do pacote corrompidos" ($corrompido -join ", ") "Baixe o pacote de novo pela Central e extraia outra vez (download incompleto ou antivirus alterou o arquivo)." }
    else { Resultado "OK" "Pacote de instalacao completo" "versao $versaoPacote" }

    if (-not $SemCorrecoes) {
        # Arquivos baixados da internet ficam marcados (Zone.Identifier); desbloquear evita bloqueios
        # do Windows/antivirus ao executar.
        try { Get-ChildItem -LiteralPath $pastaPacote -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue } catch {}
    }
}

# ---------------------------------------------------------------- Firebird / SIGECOM
$fdbOk = $false
if ([string]::IsNullOrWhiteSpace($FdbPath)) { $FdbPath = "C:\SIGECOM\SIGECOM.FDB" }
if ($FdbPath -match '^\\\\' ) {
    Resultado "BLOQUEIO" "Banco do SIGECOM em pasta de rede" $FdbPath "Instale o SigeDash no MESMO servidor onde fica o banco do SIGECOM e informe o caminho local do .FDB (ex.: C:\SIGECOM\SIGECOM.FDB)."
} elseif (-not (Test-Path -LiteralPath $FdbPath)) {
    Resultado "BLOQUEIO" "Banco do SIGECOM nao encontrado" $FdbPath "Informe o caminho correto do .FDB no instalador. O SigeDash deve ser instalado no servidor onde fica o banco do SIGECOM."
} else {
    $fdbOk = $true
    Resultado "OK" "Banco do SIGECOM encontrado" $FdbPath
}

$fbSvc = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.PathName -match 'fbserver|fb_inet_server|fb_smp_server|firebird\.exe' } | Select-Object -First 1
if (-not (TestaTcp "localhost" 3050 3000) -and $fbSvc -and $fbSvc.State -ne "Running" -and -not $SemCorrecoes) {
    try { Start-Service $fbSvc.Name -ErrorAction Stop; Start-Sleep -Seconds 3 } catch {}
    $fbSvc = Get-WmiObject Win32_Service -Filter "Name='$($fbSvc.Name)'" -ErrorAction SilentlyContinue
}
$fbNome = if ($fbSvc) { $fbSvc.Name } else { "" }
if (TestaTcp "localhost" 3050 3000) {
    Resultado "OK" "Firebird respondendo em localhost:3050" $fbNome
} elseif (-not $fbSvc) {
    Resultado "BLOQUEIO" "Servidor Firebird nao encontrado neste Windows" "" "O SigeDash precisa ser instalado no servidor do banco do SIGECOM (onde roda o Firebird)."
} elseif ($fbSvc.State -ne "Running") {
    Resultado "BLOQUEIO" "Servico do Firebird parado" $fbNome "Inicie o servico '$fbNome' (services.msc) e deixe-o como Automatico."
} else {
    Resultado "BLOQUEIO" "Firebird nao aceita conexao em localhost:3050" $fbNome "O agente conecta em localhost:3050. Confira a porta do Firebird (firebird.conf: RemoteServicePort) e o firewall local."
}

$isql = LocalizarIsql
if (-not $isql) {
    Resultado "AVISO" "isql.exe do Firebird nao encontrado" "" "O nome e o CNPJ da empresa nao serao detectados sozinhos: preencha-os no instalador."
} elseif ($fdbOk) {
    $tmpDir = if (Test-Path "C:\Windows\Temp") { "C:\Windows\Temp" } else { $env:TEMP }
    $sqlFile = Join-Path $tmpDir ("sigedash_prev_" + [guid]::NewGuid().ToString("N") + ".sql")
    try {
        @("SELECT NOMEFANTASIA FROM EMPRESA WHERE CODIGOEMPRESA = 1;", "EXIT;") | Out-File -LiteralPath $sqlFile -Encoding ASCII
        $saida = (& $isql -user SYSDBA -password masterkey $FdbPath -q -i $sqlFile 2>&1 | Out-String)
    } catch { $saida = "$_" } finally { try { [System.IO.File]::Delete($sqlFile) } catch {} }
    if ($saida -match "user name and password") {
        Resultado "BLOQUEIO" "Firebird recusou SYSDBA/masterkey" "" "O agente do SigeDash usa o usuario SYSDBA com a senha padrao do SIGECOM. Confira a senha do SYSDBA neste servidor."
    } elseif ($saida -match "Table unknown") {
        Resultado "BLOQUEIO" "O .FDB informado nao e um banco do SIGECOM" $FdbPath "Informe o caminho do banco principal do SIGECOM."
    } elseif ($saida -match "I/O error|unavailable|Unable to complete network request|Statement failed") {
        Resultado "BLOQUEIO" "Firebird nao conseguiu abrir o banco" (($saida -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 2) -join " ") "Confira se o caminho do .FDB esta correto e se o servico do Firebird tem acesso ao arquivo."
    } else {
        $nome = ($saida -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^\s*$' -and $_ -notmatch 'NOMEFANTASIA' -and $_ -notmatch '^[= ]+$' } | Select-Object -First 1)
        if ($nome) { Resultado "OK" "Leitura do banco do SIGECOM (SYSDBA)" ("empresa: " + $nome.Trim()) }
        else { Resultado "AVISO" "Nao consegui ler a empresa no banco" "" "Preencha o nome e o CNPJ da empresa no instalador." }
    }
}

# ---------------------------------------------------------------- Portas locais
$dono5000 = DonoDaPorta 5000
if (-not $dono5000) { Resultado "OK" "Porta 5000 livre (backend)" }
elseif ($dono5000 -match '^SigeDash\.Api') { Resultado "INFO" "Porta 5000 em uso pelo SigeDash atual" $dono5000 "Reinstalacao: o backend atual sera substituido." }
else { Resultado "BLOQUEIO" "Porta 5000 ocupada por outro programa" $dono5000 "O backend do SigeDash usa a porta 5000 (so localhost). Pare/desinstale esse programa ou mude a porta dele." }

$dono5432 = DonoDaPorta 5432
$pgSvc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^postgresql" } | Select-Object -First 1
if (-not $dono5432) {
    if ($pgSvc) { Resultado "INFO" "PostgreSQL instalado mas parado" $pgSvc.Name "O instalador vai inicia-lo e reaproveita-lo." }
    else { Resultado "OK" "Porta 5432 livre (o PostgreSQL 16 sera instalado)" }
} elseif ($dono5432 -match '^postgres') {
    Resultado "INFO" "PostgreSQL ja instalado neste servidor" $dono5432 "Sera reaproveitado: o instalador so cria o banco 'sigedash' (sem mexer nos outros bancos)."
} else {
    Resultado "BLOQUEIO" "Porta 5432 ocupada por outro programa" $dono5432 "O PostgreSQL usa a porta 5432. Pare esse programa antes de instalar."
}

# Instalacao anterior do PostgreSQL que falhou no meio (binarios sem banco inicializado).
$pgSobra = (Test-Path -LiteralPath "$PG_DIR\bin\psql.exe") -and -not (Test-Path -LiteralPath "$PG_DIR\data\PG_VERSION") -and -not $dono5432
if ($pgSobra) { Resultado "INFO" "Restos de uma instalacao do PostgreSQL que nao terminou" $PG_DIR "O instalador limpa e instala de novo automaticamente." }

$sigedashExiste = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @("SigeDashBackend", "SigeDashAgente", "cloudflared") }).Count
if ($sigedashExiste -gt 0) { Resultado "INFO" "SigeDash ja instalado neste servidor" "" "Reinstalacao: os servicos serao substituidos e a mesma URL sera reaproveitada." }

# ---------------------------------------------------------------- Internet
$cfg = $null
$cfPath = Join-Path $pastaPacote "cf.json"
if (Test-Path -LiteralPath $cfPath) { try { $cfg = Get-Content -LiteralPath $cfPath -Raw | ConvertFrom-Json } catch {} }

$rCf = TestaHttps "https://api.cloudflare.com/client/v4/" "GET"
if ($rCf.Ok) {
    Resultado "OK" "Internet: api.cloudflare.com"
    # Relogio errado quebra TLS e tokens. Compara com o horario do Cloudflare.
    if ($rCf.Data) {
        try {
            $remoto = [DateTime]::Parse($rCf.Data).ToUniversalTime()
            $dif = [math]::Abs(((Get-Date).ToUniversalTime() - $remoto).TotalMinutes)
            if ($dif -gt 5) { Resultado "AVISO" "Relogio do servidor errado" ("diferenca de " + [math]::Round($dif) + " min") "Acerte data/hora/fuso do Windows (sincronize com time.windows.com). Relogio errado quebra HTTPS e o login." }
        } catch {}
    }
} else {
    FalhaRede $(if ($TunnelManual) { "AVISO" } else { "BLOQUEIO" }) "api.cloudflare.com" "criacao do acesso externo" $rCf
}

# Permissoes do token da API do Cloudflare do pacote (cria tunnel + DNS). Token vencido/sem permissao
# fazia o instalador seguir sem acesso externo.
if (-not $TunnelManual -and $rCf.Ok) {
    if (-not $cfg -or -not $cfg.apiToken) {
        Resultado "BLOQUEIO" "Pacote sem a configuracao do Cloudflare (cf.json)" "" "Use o pacote oficial baixado pela Central, ou informe o token do tunnel manualmente no instalador."
    } else {
        $h = @{ Authorization = "Bearer $($cfg.apiToken)" }
        $okTun = $false; $okDns = $false
        try { $t = Invoke-RestMethod "https://api.cloudflare.com/client/v4/accounts/$($cfg.accountId)/cfd_tunnel?per_page=1" -Headers $h -TimeoutSec 20; $okTun = [bool]$t.success } catch {}
        try { $d = Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$($cfg.zoneId)/dns_records?per_page=1" -Headers $h -TimeoutSec 20; $okDns = [bool]$d.success } catch {}
        if ($okTun -and $okDns) { Resultado "OK" "Acesso a API do Cloudflare (tunnel + DNS)" }
        else {
            $falta = @(); if (-not $okTun) { $falta += "tunnel" }; if (-not $okDns) { $falta += "DNS" }
            Resultado "BLOQUEIO" "Token da API do Cloudflare recusado" ("sem permissao: " + ($falta -join " e ")) "O token do pacote (cf.json) venceu ou perdeu permissao. Avise o desenvolvimento para gerar um pacote novo."
        }
    }
}

# Tunnel: o cloudflared conecta na borda do Cloudflare na porta 7844 (TCP no modo http2 que usamos;
# UDP no QUIC). NAO e a 443. Firewall que so libera 443 derruba o acesso externo (Error 1033).
$edge = $false
foreach ($e in @("region1.v2.argotunnel.com", "region2.v2.argotunnel.com")) {
    if (TestaTcp $e 7844 6000) { $edge = $true; break }
}
if ($edge) { Resultado "OK" "Saida TCP 7844 para o Cloudflare Tunnel" }
else {
    Resultado "BLOQUEIO" "Firewall bloqueia a saida TCP 7844 (Cloudflare Tunnel)" "region1/region2.v2.argotunnel.com" "Libere a SAIDA TCP 7844 (e UDP 7844, se possivel) para region1.v2.argotunnel.com e region2.v2.argotunnel.com. Sem isso o acesso externo nao conecta (Error 1033)."
}

$precisaPg = (-not $dono5432) -and (-not $pgSvc)
$pgLocal = @((Join-Path $pastaPacote "postgresql-16-windows-x64.exe"), "C:\SigeDash\cache\postgresql-16-windows-x64.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($precisaPg -and -not $pgLocal) {
    $rPg = TestaHttps $PG_URL "HEAD"
    if ($rPg.Ok) { Resultado "OK" "Internet: get.enterprisedb.com (download do PostgreSQL)" }
    else { FalhaRede "BLOQUEIO" "get.enterprisedb.com" "download do PostgreSQL" $rPg }
}

if (-not (Test-Path -LiteralPath (Join-Path $pastaPacote "cloudflared.exe")) -and -not (Test-Path -LiteralPath "C:\SigeDash\Tunnel\cloudflared.exe")) {
    $rGh = TestaHttps "https://github.com/cloudflare/cloudflared/releases" "HEAD"
    if ($rGh.Ok) { Resultado "OK" "Internet: github.com (download do cloudflared)" }
    else { FalhaRede "BLOQUEIO" "github.com" "download do cloudflared" $rGh }
}

$rApi = TestaHttps "https://api.github.com/" "GET"
if ($rApi.Ok) { Resultado "OK" "Internet: api.github.com (atualizacoes automaticas)" }
else { FalhaRede "AVISO" "api.github.com" "atualizacoes automaticas" $rApi }

$centralUrl = $null
$cjPath = Join-Path $pastaPacote "central.json"
if (Test-Path -LiteralPath $cjPath) { try { $centralUrl = ("" + (Get-Content -LiteralPath $cjPath -Raw | ConvertFrom-Json).Url).TrimEnd('/') } catch {} }
if ($centralUrl) {
    $rC = TestaHttps "$centralUrl/health" "GET"
    if ($rC.Ok -and $rC.Codigo -lt 500) { Resultado "OK" "Internet: SigeDash Central" }
    elseif ($rC.Ok) { Resultado "AVISO" "SigeDash Central fora do ar" "HTTP $($rC.Codigo)" "A instalacao funciona; o cliente aparece na Central quando ela voltar (rode registrar-central.ps1)." }
    else { FalhaRede "AVISO" (([Uri]$centralUrl).Host) "SigeDash Central" $rC }
}

# ---------------------------------------------------------------- Resumo
$bloqueios = @($itens | Where-Object { $_.nivel -eq "BLOQUEIO" }).Count
$avisos    = @($itens | Where-Object { $_.nivel -eq "AVISO" }).Count

Write-Host ""
Write-Host ("=" * 64) -ForegroundColor Cyan
if ($bloqueios -gt 0) {
    Write-Host "  PRE-VERIFICACAO: $bloqueios BLOQUEIO(S) - a instalacao NAO vai comecar." -ForegroundColor Red
    Write-Host "  Resolva os itens [BLOQUEIO] acima (a linha '->' diz como) e rode de novo." -ForegroundColor Red
    if ($script:reiniciar) { Write-Host "  >>> REINICIE O SERVIDOR antes de tentar de novo. <<<" -ForegroundColor Red }
} elseif ($avisos -gt 0) {
    Write-Host "  PRE-VERIFICACAO OK, com $avisos aviso(s). A instalacao pode seguir." -ForegroundColor Yellow
} else {
    Write-Host "  PRE-VERIFICACAO OK - servidor pronto para a instalacao." -ForegroundColor Green
}
Write-Host ("=" * 64) -ForegroundColor Cyan

try {
    New-Item -ItemType Directory -Path (Split-Path $SAIDA_JSON) -Force | Out-Null
    $resultado = [ordered]@{
        data      = (Get-Date).ToString("s")
        maquina   = $env:COMPUTERNAME
        os        = $osNome
        bloqueios = $bloqueios
        avisos    = $avisos
        reiniciar = $script:reiniciar
        itens     = $itens
    }
    [System.IO.File]::WriteAllText($SAIDA_JSON, ($resultado | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
} catch {}

if ($bloqueios -gt 0) { exit 2 }
exit 0
