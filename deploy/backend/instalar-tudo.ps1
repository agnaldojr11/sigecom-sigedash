<#
.SYNOPSIS
    Instalacao completa do SigeDash no servidor do cliente.
.DESCRIPTION
    Executa em sequencia:
      1. PostgreSQL 16  (banco de dados)
      2. SigeDash Backend  (API + PWA como Windows Service)
      3. SigeDash Agente   (coleta dados do Firebird)
      4. Cloudflare Tunnel (acesso externo HTTPS)
      5. Cria o usuario do cliente no sistema

    Todos os passos geram log em C:\SigeDash\install.log.

.PARAMETER NomeCliente
    Nome do cliente. Se omitido, detectado automaticamente via NOMEFANTASIA do banco Firebird.

.PARAMETER FdbPath
    Caminho completo para o arquivo .FDB do Sigecom no servidor.
    Padrao: C:\SIGECOM\SIGECOM.FDB (caminho padrao de instalacao do Sigecom)

.PARAMETER TunnelToken
    Token do tunel Cloudflare (obtido no painel Zero Trust antes de rodar este script).
    Deixe em branco para pular a instalacao do tunel (instale manualmente depois).

.PARAMETER SigeDashSenha
    Senha do banco PostgreSQL. Gerada automaticamente se omitida.

.EXAMPLE
    .\instalar-tudo.ps1 -TunnelToken "eyJhIjoiMT..."
    .\instalar-tudo.ps1 -FdbPath "D:\SIGECOM\SIGECOM.FDB" -TunnelToken "eyJhIjoiMT..."
    .\instalar-tudo.ps1 -NomeCliente "Amaral Ferragens" -TunnelToken "eyJhIjoiMT..."
#>
param(
    [string]$NomeCliente       = "",
    [string]$Cnpj              = "",
    [string]$FdbPath           = "C:\SIGECOM\SIGECOM.FDB",

    # Limite de dispositivos/usuarios do plano comercial (0 = ilimitado). -1 = perguntar ao instalador.
    [int]   $LimiteDispositivos = -1,

    [string]$TunnelToken       = "",
    [string]$SigeDashSenha     = "",

    # Prossegue mesmo se o cliente ja existir no Cloudflare (por padrao, aborta para evitar duplicidade).
    [switch]$Force,

    # REINSTALACAO: cliente ja existe no Cloudflare e queremos REUTILIZAR o mesmo tunnel/DNS (mesma URL),
    # tipico quando o servidor foi trocado. Reaproveita em vez de duplicar. Sem isto, um cliente ja
    # existente ABORTA a instalacao (a menos que -Force).
    [switch]$Reinstalar
)

$ErrorActionPreference = "Stop"
$LOG_GERAL = "C:\SigeDash\install.log"
$SCRIPT_DIR = $PSScriptRoot

function Log($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    New-Item -ItemType Directory -Path "C:\SigeDash" -Force | Out-Null
    Add-Content $LOG_GERAL $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Titulo($msg) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Log ">>> $msg"
}

function Sucesso($msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
    Log "[OK] $msg"
}

function Falha($msg) {
    Write-Host "[ERRO] $msg" -ForegroundColor Red
    Log "[ERRO] $msg"

    # Junta os logs das etapas em um lugar so, para facilitar o suporte.
    $pgLog = "$env:TEMP\sigedash-postgres-install.log"
    if (Test-Path $pgLog) { try { Copy-Item $pgLog "C:\SigeDash\postgres-install.log" -Force } catch {} }

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "  A INSTALACAO FALHOU" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "  Motivo: $msg" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  COMO RESOLVER:" -ForegroundColor Cyan
    Write-Host "   1) Rode o diagnostico (mostra a causa de cada componente):"
    Write-Host "        powershell -ExecutionPolicy Bypass -File `"$SCRIPT_DIR\diagnostico.ps1`""
    Write-Host "   2) Para tentar de novo do zero, limpe tudo e reinstale:"
    Write-Host "        powershell -ExecutionPolicy Bypass -File `"$SCRIPT_DIR\desinstalar-tudo.ps1`""
    Write-Host "        (depois rode este instalador novamente)"
    Write-Host ""
    Write-Host "  LOGS PARA O SUPORTE:" -ForegroundColor Cyan
    Write-Host "   - Geral    : $LOG_GERAL"
    Write-Host "   - PostgreSQL: C:\SigeDash\postgres-install.log (copiado agora, se existia)"
    Write-Host "   - Backend  : C:\SigeDash\Backend\install.log"
    Write-Host "   - Tunnel   : C:\SigeDash\Tunnel\tunnel-install.log"
    Write-Host "   - Event Viewer -> Logs de Aplicativos (erros do .NET/servico)"
    Write-Host ("=" * 60) -ForegroundColor Red
    Log "Instalacao abortada. Ver diagnostico.ps1 / desinstalar-tudo.ps1."
    exit 1
}

# Verifica no Cloudflare se o cliente ja existe (tunnel com o mesmo nome OU DNS com o mesmo hostname).
# Retorna hashtable com o que encontrou, ou $null se nao der para verificar (sem cf.json).
# Usado para AVISAR e ABORTAR antes de instalar qualquer coisa, evitando cliente/tunnel duplicado.
function VerificarClienteCloudflare($nomeCliente, $scriptDir) {
    $cfConfig = Join-Path $scriptDir "cf.json"
    if (-not (Test-Path $cfConfig)) {
        Log "cf.json ausente - pulando verificacao de duplicidade no Cloudflare."
        return $null
    }
    $cf      = Get-Content $cfConfig | ConvertFrom-Json
    $headers = @{ "Authorization" = "Bearer $($cf.apiToken)"; "Content-Type" = "application/json" }

    # Mesmo slug/hostname/nome usados em CriarTunnelCloudflare (tem que casar exatamente).
    $slug = ($nomeCliente -replace '[^a-zA-Z0-9]', '').ToLower()
    if ($slug.Length -gt 20) { $slug = $slug.Substring(0, 20) }
    $tunnelName = "sigedash-$slug"
    $hostname   = "$slug.$($cf.dominio)"

    $r = @{ TunnelExiste = $false; TunnelId = $null; DnsExiste = $false; TunnelName = $tunnelName; Hostname = $hostname }
    try {
        $rt = Invoke-RestMethod "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel?name=$tunnelName&is_deleted=false" `
            -Headers $headers -Method GET
        if ($rt.result -and @($rt.result).Count -gt 0) { $r.TunnelExiste = $true; $r.TunnelId = $rt.result[0].id }
    } catch { Log "AVISO: nao foi possivel consultar tuneis no Cloudflare: $_" }
    try {
        $rd = Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$($cf.zoneId)/dns_records?name=$hostname" `
            -Headers $headers -Method GET
        if ($rd.result -and @($rd.result).Count -gt 0) { $r.DnsExiste = $true }
    } catch { Log "AVISO: nao foi possivel consultar DNS no Cloudflare: $_" }
    return $r
}

function CriarTunnelCloudflare($nomeCliente, $scriptDir) {
    $cfConfig = Join-Path $scriptDir "cf.json"
    if (-not (Test-Path $cfConfig)) {
        Log "cf.json nao encontrado - tunnel sera configurado manualmente."
        return $null
    }
    $cf      = Get-Content $cfConfig | ConvertFrom-Json
    $headers = @{ "Authorization" = "Bearer $($cf.apiToken)"; "Content-Type" = "application/json" }

    # Slug: "5 Estrelas Comercial" -> "5estrelas"
    $slug = ($nomeCliente -replace '[^a-zA-Z0-9]', '').ToLower()
    if ($slug.Length -gt 20) { $slug = $slug.Substring(0, 20) }
    $tunnelName = "sigedash-$slug"
    $hostname   = "$slug.$($cf.dominio)"

    # 1) Idempotente: se ja existe um tunnel com esse nome, REUTILIZA (reinstalacao = mesma URL, sem
    #    duplicar). So cria um novo quando nao existe.
    $tunnelId = $null
    $reused   = $false
    try {
        $rt = Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel?name=$tunnelName&is_deleted=false" `
            -Headers $headers -Method GET
        if ($rt.result -and @($rt.result).Count -gt 0) {
            $tunnelId = $rt.result[0].id
            $reused   = $true
            Log "Tunnel '$tunnelName' ja existe ($tunnelId) - REUTILIZANDO (reinstalacao, mesma URL)."
        }
    } catch { Log "AVISO: nao foi possivel consultar tuneis existentes: $_" }

    if (-not $tunnelId) {
        Log "Criando tunnel Cloudflare: $tunnelName ..."
        # Cria o tunnel (segredo via CSPRNG, nao Get-Random)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $secretBytes = New-Object byte[] 32; $rng.GetBytes($secretBytes)
        $body = @{
            name          = $tunnelName
            tunnel_secret = [Convert]::ToBase64String($secretBytes)
        } | ConvertTo-Json
        try {
            $resp     = Invoke-RestMethod `
                "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel" `
                -Method POST -Headers $headers -Body $body
            $tunnelId = $resp.result.id
            Log "Tunnel criado: $tunnelId"
        } catch {
            Log "AVISO: erro ao criar tunnel Cloudflare: $_"
            return $null
        }
    }

    # 2) Configura ingress (hostname -> localhost:5000). Idempotente: PUT reaplica sempre.
    $ingressBody = @{
        config = @{
            ingress = @(
                @{ hostname = $hostname; service = "http://localhost:5000" },
                @{ service  = "http_status:404" }
            )
        }
    } | ConvertTo-Json -Depth 6
    try {
        Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel/$tunnelId/configurations" `
            -Method PUT -Headers $headers -Body $ingressBody | Out-Null
        Log "Ingress configurado: $hostname -> localhost:5000"
    } catch {
        Log "AVISO: erro ao configurar ingress: $_"
    }

    # 3) DNS CNAME (upsert): atualiza se ja existir apontando para o tunnel, senao cria.
    $dnsContent = "$tunnelId.cfargotunnel.com"
    $dnsBody = @{ type = "CNAME"; name = $slug; content = $dnsContent; proxied = $true; ttl = 1 } | ConvertTo-Json
    $dnsId = $null
    try {
        $rd = Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/zones/$($cf.zoneId)/dns_records?name=$hostname" `
            -Headers $headers -Method GET
        if ($rd.result -and @($rd.result).Count -gt 0) { $dnsId = $rd.result[0].id }
    } catch { Log "AVISO: nao foi possivel consultar DNS existente: $_" }
    try {
        if ($dnsId) {
            Invoke-RestMethod `
                "https://api.cloudflare.com/client/v4/zones/$($cf.zoneId)/dns_records/$dnsId" `
                -Method PUT -Headers $headers -Body $dnsBody | Out-Null
            Log "DNS atualizado: https://$hostname -> $dnsContent"
        } else {
            Invoke-RestMethod `
                "https://api.cloudflare.com/client/v4/zones/$($cf.zoneId)/dns_records" `
                -Method POST -Headers $headers -Body $dnsBody | Out-Null
            Log "DNS criado: https://$hostname"
        }
    } catch {
        Log "AVISO: erro ao configurar DNS: $_"
    }

    # 4) Obtem o token do tunnel (funciona tanto para tunnel novo quanto reutilizado)
    try {
        $tokenResp = Invoke-RestMethod `
            "https://api.cloudflare.com/client/v4/accounts/$($cf.accountId)/cfd_tunnel/$tunnelId/token" `
            -Headers $headers
        Log "Token do tunnel obtido com sucesso."
        return @{ Token = $tokenResp.result; Url = "https://$hostname"; Reused = $reused }
    } catch {
        Log "AVISO: erro ao obter token do tunnel: $_"
        return $null
    }
}

# Le um campo da tabela EMPRESA (CODIGOEMPRESA=1) do Firebird via isql. Usado para auto-detectar
# NOMEFANTASIA e CNPJ quando nao informados no install.
function BuscarCampoEmpresa($fdbPath, $campo) {
    $candidatos = @(
        "C:\Program Files\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_2_5\bin\isql.exe",
        "C:\Program Files\Firebird\Firebird_3_0\bin\isql.exe",
        "C:\Program Files (x86)\Firebird\Firebird_3_0\bin\isql.exe"
    )
    $isql = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $isql) {
        Log "AVISO: isql.exe nao encontrado - informe os dados manualmente."
        return $null
    }
    $sqlFile = Join-Path $env:TEMP "sigedash_query.sql"
    @("SELECT $campo FROM EMPRESA WHERE CODIGOEMPRESA = 1;", "EXIT;") |
        Out-File $sqlFile -Encoding ASCII
    try {
        $saida = & $isql -user SYSDBA -password masterkey $fdbPath -q -i $sqlFile 2>&1
        $val  = $saida | Where-Object {
            $_ -and
            $_ -notmatch '^\s*$' -and
            $_ -notmatch ('^\s*' + [regex]::Escape($campo)) -and
            $_ -notmatch '^[= ]+$' -and
            $_ -notmatch '^Database:'
        } | Select-Object -First 1
        return ($val -as [string]).Trim()
    } catch {
        Log "AVISO: erro ao consultar Firebird ($campo): $_"
        return $null
    } finally {
        Remove-Item $sqlFile -ErrorAction SilentlyContinue
    }
}
function BuscarNomeFantasia($fdbPath) { return BuscarCampoEmpresa $fdbPath "NOMEFANTASIA" }

# Verifica privilegio de admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador (clique direito -> Executar como administrador)."
    exit 1
}

# Pre-requisito do AGENTE: .NET Framework 4.8 (Release >= 528040). Em Windows Server 2016/2012R2 pode
# faltar. O backend e self-contained (nao precisa de runtime), mas o agente e framework-dependent -
# sem 4.8 o servico SigeDashAgente nao inicia (os dados nao sincronizam). Aviso NAO-fatal.
try {
    $ndp = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop
    if ([int]$ndp.Release -lt 528040) {
        Log "AVISO: .NET Framework 4.8 ausente (Release=$($ndp.Release)). O AGENTE pode nao iniciar."
        Log "       Instale o .NET Framework 4.8 (https://dotnet.microsoft.com/download/dotnet-framework/net48) e rode de novo, ou o agente so sincronizara apos instalar o 4.8."
    }
} catch {
    Log "AVISO: nao foi possivel confirmar o .NET Framework 4.8 - se o agente nao iniciar, instale o 4.8."
}

# Auto-detecta nome do cliente via Firebird se nao informado
if ([string]::IsNullOrWhiteSpace($NomeCliente)) {
    Log "NomeCliente nao informado — buscando NOMEFANTASIA no banco Firebird..."
    $NomeCliente = BuscarNomeFantasia $FdbPath
    if ([string]::IsNullOrWhiteSpace($NomeCliente)) {
        Falha "Nao foi possivel detectar o nome do cliente. Informe -NomeCliente manualmente."
    }
    Log "Nome detectado automaticamente: $NomeCliente"
}

# Auto-detecta o CNPJ via Firebird se nao informado (identidade forte na Central; nao-fatal se faltar)
if ([string]::IsNullOrWhiteSpace($Cnpj)) {
    $Cnpj = BuscarCampoEmpresa $FdbPath "CNPJ"
    if (-not [string]::IsNullOrWhiteSpace($Cnpj)) { Log "CNPJ detectado automaticamente: $Cnpj" }
    else { Log "CNPJ nao detectado - registro na Central usara so o nome." }
}

# ============================================================
# Pre-check: cliente ja existe no Cloudflare? (so quando vamos AUTO-CRIAR o tunnel)
# ============================================================
if ([string]::IsNullOrWhiteSpace($TunnelToken)) {
    $cfCheck = VerificarClienteCloudflare $NomeCliente $SCRIPT_DIR
    if ($cfCheck -and ($cfCheck.TunnelExiste -or $cfCheck.DnsExiste)) {
        Write-Host ""
        Write-Host ("!" * 62) -ForegroundColor Yellow
        Write-Host "  ATENCAO: o cliente '$NomeCliente' JA EXISTE no Cloudflare." -ForegroundColor Yellow
        if ($cfCheck.TunnelExiste) { Write-Host "    - Tunnel: $($cfCheck.TunnelName)  (id $($cfCheck.TunnelId))" -ForegroundColor Yellow }
        if ($cfCheck.DnsExiste)    { Write-Host "    - DNS   : $($cfCheck.Hostname)" -ForegroundColor Yellow }
        Write-Host ("!" * 62) -ForegroundColor Yellow
        Log "Cliente '$NomeCliente' ja existe no Cloudflare (tunnel=$($cfCheck.TunnelExiste) dns=$($cfCheck.DnsExiste))."

        if ($Reinstalar -or $Force) {
            Log "Modo REINSTALACAO: o tunnel/DNS existente sera REUTILIZADO (mesma URL), sem duplicar."
        } else {
            # Tenta confirmar interativamente; em execucao nao-interativa, aborta com instrucao clara.
            $resp = $null
            try { $resp = Read-Host "  E uma REINSTALACAO deste mesmo cliente (trocou de servidor)? Reutilizar o tunnel/URL existente? (S/N)" } catch { $resp = $null }
            if ($resp -match '^[SsYy]') {
                $Reinstalar = $true
                Log "Reinstalacao confirmada pelo operador - reutilizando o tunnel/URL existente."
            } else {
                Falha "Instalacao ABORTADA para evitar duplicidade. Se for REINSTALACAO deste mesmo cliente (mesma URL), rode com -Reinstalar. Se for um cliente diferente, use outro nome."
            }
        }
    }
}

# Gera senha do banco se nao informada
if ([string]::IsNullOrWhiteSpace($SigeDashSenha)) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 24; $rng.GetBytes($bytes)   # CSPRNG (nao Get-Random)
    $SigeDashSenha = [Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', ''
    $SigeDashSenha = ($SigeDashSenha + "Sd1!").Substring(0, 16)
    Log "Senha do banco gerada automaticamente."
}

Log ""
Log "=== Instalacao SigeDash - Cliente: $NomeCliente ==="
Log "FDB     : $FdbPath"
Write-Host "Senha PG: $SigeDashSenha" -ForegroundColor Yellow   # console apenas (segredo, fora do log)
Log ""

# ============================================================
Titulo "PASSO 1 - PostgreSQL 16"
# ============================================================
$scriptPg = Join-Path $SCRIPT_DIR "instalar-postgres.ps1"
if (-not (Test-Path $scriptPg)) { Falha "instalar-postgres.ps1 nao encontrado em $SCRIPT_DIR" }

try {
    & $scriptPg -SigeDashSenha $SigeDashSenha
    # exit 1 em script filho nao lanca excecao - checar $LASTEXITCODE explicitamente
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Falha "instalar-postgres.ps1 falhou com codigo $LASTEXITCODE"
    }
    Sucesso "PostgreSQL instalado e configurado."
} catch {
    Falha "Erro no PostgreSQL: $_"
}

# ============================================================
Titulo "PASSO 2 - SigeDash Backend"
# ============================================================
$scriptBack = Join-Path $SCRIPT_DIR "instalar-backend.ps1"
if (-not (Test-Path $scriptBack)) { Falha "instalar-backend.ps1 nao encontrado em $SCRIPT_DIR" }

try {
    & $scriptBack -PostgresSenha $SigeDashSenha -PublishDir $SCRIPT_DIR
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Falha "instalar-backend.ps1 falhou com codigo $LASTEXITCODE"
    }
    # Extrai a AdminKey do log de instalacao
    $adminKeyLine = Get-Content "C:\SigeDash\Backend\install.log" -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match "AdminKey\s*:" } | Select-Object -Last 1
    if ($adminKeyLine -match "AdminKey\s*:\s*(.+)$") {
        $AdminKey = $Matches[1].Trim()
        Log "AdminKey capturada do log do backend."
    } else {
        # Fallback: le direto do appsettings.Production.json
        $appsettings = Get-Content "C:\SigeDash\Backend\appsettings.Production.json" | ConvertFrom-Json
        $AdminKey    = $appsettings.AdminKey
        Log "AdminKey lida do appsettings.Production.json."
    }
    Sucesso "Backend instalado."
    Write-Host "AdminKey: $AdminKey" -ForegroundColor Yellow   # console apenas (segredo, fora do log)
} catch {
    Falha "Erro no backend: $_"
}

# ============================================================
# Limite de dispositivos do plano (comercial) - pergunta se nao veio por parametro.
# ============================================================
if ($LimiteDispositivos -lt 0) {
    Write-Host ""
    Write-Host "  PLANO COMERCIAL - Licenciamento por dispositivo" -ForegroundColor Cyan
    Write-Host "  Quantos dispositivos/usuarios este CNPJ pode usar no SigeDash?" -ForegroundColor White
    Write-Host "  (cada usuario = 1 dispositivo; digite 0 para ilimitado)" -ForegroundColor DarkGray
    $resp = Read-Host "  Limite de dispositivos"
    $n = 0
    if (-not [int]::TryParse(($resp -replace '\D',''), [ref]$n)) { $n = 0 }
    $LimiteDispositivos = $n
}
Log ("Limite de dispositivos do plano: " + $(if ($LimiteDispositivos -gt 0) { $LimiteDispositivos } else { 'ilimitado' }))

# ============================================================
Titulo "PASSO 3 - SigeDash Agente"
# ============================================================
# O agente agora e instalado via instalar-agente.ps1 (binarios + servico, nao-interativo).
# Os binarios ficam na subpasta 'agente' do pacote.
$scriptAgente = Join-Path $SCRIPT_DIR "instalar-agente.ps1"
$agenteSrc    = Join-Path $SCRIPT_DIR "agente"

if (-not (Test-Path $scriptAgente)) {
    Log "AVISO: instalar-agente.ps1 nao encontrado em $SCRIPT_DIR"
    Log "Instale o agente manualmente depois."
} elseif (-not (Test-Path (Join-Path $agenteSrc "SigeDash.Agente.exe"))) {
    Log "AVISO: binarios do agente nao encontrados em $agenteSrc"
    Log "O pacote pode ter sido gerado sem o agente. Instale manualmente depois."
} else {
    try {
        & $scriptAgente `
            -BackendUrl         "http://localhost:5000" `
            -AdminKey           $AdminKey `
            -ClienteNome        $NomeCliente `
            -FdbPath            $FdbPath `
            -LimiteDispositivos $LimiteDispositivos `
            -AgenteSrc          $agenteSrc
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Log "AVISO: instalar-agente.ps1 retornou codigo $LASTEXITCODE. Verifique manualmente."
        } else {
            Sucesso "Agente instalado e configurado."
        }
    } catch {
        Log "AVISO: erro ao instalar agente: $_"
        Log "Execute manualmente: instalar-agente.ps1"
    }
}

# ============================================================
Titulo "PASSO 4 - Cloudflare Tunnel"
# ============================================================
$TunnelUrl = ""

if ([string]::IsNullOrWhiteSpace($TunnelToken)) {
    Log "TunnelToken nao informado - tentando criar automaticamente via API Cloudflare..."
    $cfResult = CriarTunnelCloudflare $NomeCliente $SCRIPT_DIR
    if ($cfResult) {
        $TunnelToken = $cfResult.Token
        $TunnelUrl   = $cfResult.Url
        if ($cfResult.Reused) { Sucesso "Tunnel Cloudflare REUTILIZADO (mesma URL): $TunnelUrl" }
        else { Sucesso "Tunnel Cloudflare criado: $TunnelUrl" }
    }
}

if (-not [string]::IsNullOrWhiteSpace($TunnelToken)) {
    $scriptTunnel = Join-Path $SCRIPT_DIR "instalar-tunnel.ps1"
    if (-not (Test-Path $scriptTunnel)) { Falha "instalar-tunnel.ps1 nao encontrado em $SCRIPT_DIR" }
    try {
        & $scriptTunnel -TunnelToken $TunnelToken
        Sucesso "Cloudflare Tunnel instalado."
    } catch {
        Log "AVISO: erro no tunnel: $_"
        Log "Instale manualmente com: instalar-tunnel.ps1 -TunnelToken <TOKEN>"
    }
} else {
    Log "AVISO: tunnel nao configurado. Para instalar manualmente depois:"
    Log "  1. Execute .\configurar-cf.ps1 na maquina de desenvolvimento"
    Log "  2. Gere novo pacote com build-deploy.ps1"
    Log "  OU informe -TunnelToken ao executar instalar-tudo.ps1"
}

# ============================================================
Titulo "PASSO 5 - Registro na SigeDash Central"
# ============================================================
# Auto-registro no fim do install (uma vez, controlado). Idempotente e nao-fatal.
if (-not [string]::IsNullOrWhiteSpace($NomeCliente)) {
    $scriptCentral = Join-Path $SCRIPT_DIR "registrar-central.ps1"
    if (Test-Path $scriptCentral) {
        try { & $scriptCentral -Nome $NomeCliente -Cnpj $Cnpj -BackendDir "C:\SigeDash\Backend" -ScriptDir $SCRIPT_DIR }
        catch { Log "AVISO: registro na Central falhou: $_ (nao impede a instalacao)." }
    } else {
        Log "registrar-central.ps1 ausente - telemetria nao configurada (adicione central.json ao pacote)."
    }
} else {
    Log "NomeCliente vazio - pulando registro na Central."
}

# ============================================================
Titulo "PASSO 6 - Verificacao final"
# ============================================================
# O install so pode dizer "sucesso" se o cliente estiver REALMENTE usavel: a empresa precisa
# aparecer no backend, senao o PWA mostra "Nenhuma empresa cadastrada" e o banco nao carrega.
function EmpresaRegistrada($nome) {
    try {
        $emp = Invoke-RestMethod "http://localhost:5000/auth/empresas" -TimeoutSec 10
        return [bool]($emp | Where-Object { $_.nome -eq $nome })
    } catch { return $false }
}

# Espera o backend responder (ate ~30s) antes de verificar.
$backendUp = $false
for ($i = 0; $i -lt 10; $i++) {
    try { Invoke-RestMethod "http://localhost:5000/auth/empresas" -TimeoutSec 5 | Out-Null; $backendUp = $true; break }
    catch { Start-Sleep -Seconds 3 }
}
if (-not $backendUp) {
    Falha "O backend nao respondeu em http://localhost:5000 apos a instalacao. O app nao vai funcionar. Rode diagnostico.ps1 para ver a causa (servico/porta/banco)."
}

$clienteOk = EmpresaRegistrada $NomeCliente
if (-not $clienteOk) {
    Log "A empresa '$NomeCliente' NAO aparece no backend - tentando registrar novamente..."
    $scriptConf = Join-Path $SCRIPT_DIR "configurar-cliente.ps1"
    if (Test-Path $scriptConf) {
        try {
            & $scriptConf -BackendUrl "http://localhost:5000" -AdminKey $AdminKey `
                -ClienteNome $NomeCliente -FdbPath $FdbPath -LimiteDispositivos $LimiteDispositivos `
                -ConfigDir "C:\Program Files\SistemasBr\SigeDash\Config"
        } catch { Log "AVISO: nova tentativa de registro falhou: $_" }
        Start-Sleep -Seconds 2
        $clienteOk = EmpresaRegistrada $NomeCliente
    } else {
        Log "AVISO: configurar-cliente.ps1 nao encontrado em $SCRIPT_DIR."
    }
}

if ($clienteOk) {
    Sucesso "Empresa '$NomeCliente' cadastrada e visivel no login."
} else {
    Falha ("A empresa '$NomeCliente' NAO foi cadastrada no backend - o app mostraria 'Nenhuma empresa cadastrada'. " +
           "Causas comuns: o banco Firebird nao foi encontrado em '$FdbPath', ou o backend/registro falhou. " +
           "Rode diagnostico.ps1 para confirmar; se o .FDB estiver em outro caminho, reinstale com -FdbPath correto.")
}

# Aviso NAO-fatal se a telemetria/Central nao ficou configurada (o cliente funciona mesmo assim).
try {
    $appJsonVerif = "C:\SigeDash\Backend\appsettings.Production.json"
    if (Test-Path $appJsonVerif) {
        $jVerif = Get-Content $appJsonVerif -Raw | ConvertFrom-Json
        if ($jVerif.Central -and $jVerif.Central.Url) { Sucesso "Registrado na SigeDash Central (telemetria ativa)." }
        else { Log "AVISO: cliente NAO registrado na Central (telemetria off). Rode registrar-central.ps1 quando houver internet + central.json." }
    }
} catch {}

# Verifica o ACESSO EXTERNO (DNS + tunnel) de ponta a ponta. So quando sabemos a URL (tunnel
# auto-criado). Pega o caso em que o DNS/hostname nao foi criado no Cloudflare: o cliente veria
# "nao e possivel acessar o site" (ERR_NAME_NOT_RESOLVED) ou Error 1033 (tunnel fora).
if (-not [string]::IsNullOrWhiteSpace($TunnelUrl)) {
    Log "Verificando o acesso externo em $TunnelUrl (DNS + tunnel)..."
    $pubOk = $false
    for ($k = 0; $k -lt 12; $k++) {   # ate ~60s (o DNS do Cloudflare costuma propagar em segundos)
        try { Invoke-WebRequest "$TunnelUrl/health" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop | Out-Null; $pubOk = $true; break }
        catch { Start-Sleep -Seconds 5 }
    }
    if ($pubOk) {
        Sucesso "Acesso externo OK: $TunnelUrl"
    } else {
        Write-Host ""
        Write-Host ("!" * 60) -ForegroundColor Yellow
        Write-Host "  [ATENCAO] O acesso externo NAO respondeu: $TunnelUrl" -ForegroundColor Yellow
        Write-Host "  O cliente veria 'nao e possivel acessar o site' (DNS) ou Error 1033 (tunnel)." -ForegroundColor Yellow
        Write-Host "  Verifique no painel Cloudflare se o DNS/Public Hostname do tunnel foi criado e se" -ForegroundColor Yellow
        Write-Host "  o servico cloudflared esta rodando. Rode diagnostico.ps1 para o detalhe." -ForegroundColor Yellow
        Write-Host "  Entregue ao cliente a URL EXATA (com '.br'): $TunnelUrl" -ForegroundColor Yellow
        Write-Host ("!" * 60) -ForegroundColor Yellow
        Log "AVISO: acesso externo nao verificado ($TunnelUrl) - possivel DNS/hostname nao criado ou tunnel fora."
    }
} else {
    Log "AVISO: URL do tunnel desconhecida (token manual) - verifique o acesso externo e o DNS/Public Hostname no painel Cloudflare."
}

# ============================================================
Titulo "INSTALACAO CONCLUIDA"
# ============================================================
Log ""
Log "Resumo da instalacao:"
Log "  Cliente   : $NomeCliente"
Log "  Backend   : http://localhost:5000 (servico SigeDashBackend)"
Log "  Agente    : servico SigeDashAgente"
Log "  PostgreSQL: servico postgresql-x64-16"
if (-not [string]::IsNullOrWhiteSpace($TunnelToken)) {
    if (-not [string]::IsNullOrWhiteSpace($TunnelUrl)) {
        Log "  Tunnel    : $TunnelUrl (acesso externo HTTPS)"
    } else {
        Log "  Tunnel    : servico cloudflared ativo (verifique URL no painel Cloudflare)"
    }
}
Log ""
Write-Host "AdminKey para gerenciar clientes: $AdminKey" -ForegroundColor Yellow   # console apenas (segredo)
Log ""
Log "Log completo salvo em: $LOG_GERAL"
Log ""

# Destaque da URL do cliente
if (-not [string]::IsNullOrWhiteSpace($TunnelUrl)) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "  URL DO CLIENTE (compartilhe agora):" -ForegroundColor Green
    Write-Host ""
    Write-Host "  $TunnelUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Acesso pelo celular, tablet ou computador." -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Log "URL do cliente: $TunnelUrl"
}

Log "PROXIMOS PASSOS:"
Log "  1. Aguarde 30 minutos para o agente sincronizar os primeiros dados"
Log "  2. Envie a URL acima ao cliente para acesso pelo celular"
Log "  3. Faca login com as credenciais criadas automaticamente"