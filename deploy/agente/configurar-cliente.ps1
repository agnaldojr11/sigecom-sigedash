param(
    [string]$BackendUrl,
    [string]$AdminKey,
    [string]$ClienteNome,
    [string]$FdbPath,
    [string]$Sysdba      = "masterkey",
    [string]$ConfigDir    = "C:\SIGECOM\SIGEDASH"
)

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
    Add-Content "$ConfigDir\setup.log" "[$ts] $msg" -ErrorAction SilentlyContinue
}

Log "=== SigeDash — Configuração do Cliente ==="
Log "Backend  : $BackendUrl"
Log "Cliente  : $ClienteNome"
Log "Banco FDB: $FdbPath"

# ── 1. Valida banco FDB ───────────────────────────────────────────────────────
if (-not (Test-Path $FdbPath)) {
    Log "ERRO: Arquivo FDB não encontrado: $FdbPath"
    exit 1
}

# ── 2. Registra o cliente no backend ─────────────────────────────────────────
try {
    $bodyCliente = @{
        nome          = $ClienteNome
        codigoEmpresa = 1
        nomeLoja      = "Matriz"
    } | ConvertTo-Json

    $respCliente = Invoke-RestMethod `
        -Uri     "$BackendUrl/admin/clientes" `
        -Method  POST `
        -Headers @{ "X-Admin-Key" = $AdminKey; "Content-Type" = "application/json" } `
        -Body    $bodyCliente

    $chaveApi = $respCliente.chaveApi
    Log "Cliente registrado. ChaveApi: $chaveApi"
}
catch {
    # Se cliente já existe, busca a chave existente
    if ($_.Exception.Response.StatusCode -eq 409) {
        Log "Cliente já existe no backend — usando cadastro existente."
        try {
            $todos = Invoke-RestMethod `
                -Uri     "$BackendUrl/admin/clientes" `
                -Method  GET `
                -Headers @{ "X-Admin-Key" = $AdminKey }
            $chaveApi = ($todos | Where-Object { $_.nome -eq $ClienteNome }).chaveApi
            Log "ChaveApi recuperada: $chaveApi"
        }
        catch {
            Log "ERRO ao recuperar cliente existente: $_"
            exit 2
        }
    }
    else {
        Log "ERRO ao registrar cliente: $_"
        exit 2
    }
}

# ── 3. Grava agente.config.json ───────────────────────────────────────────────
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

$fdbEscaped = $FdbPath -replace '\\', '\\'
$connStr    = "User=SYSDBA;Password=$Sysdba;Database=$fdbEscaped;" +
              "DataSource=localhost;Port=3050;Dialect=3;Charset=ISO8859_1;" +
              "Pooling=true;ConnectionLifetime=60"

$config = [ordered]@{
    FirebirdConnectionString = $connStr
    CodigoEmpresa            = 1
    BackendUrl               = $BackendUrl
    ChaveCliente             = $chaveApi
    PastaSql                 = "Indicadores/sql"
}

$config | ConvertTo-Json -Depth 3 | Set-Content "$ConfigDir\agente.config.json" -Encoding UTF8
Log "agente.config.json gravado em $ConfigDir"

# ── 4. Reinicia o serviço (se já instalado) ───────────────────────────────────
$svc = Get-Service "SigeDashAgente" -ErrorAction SilentlyContinue
if ($svc) {
    Restart-Service "SigeDashAgente" -Force -ErrorAction SilentlyContinue
    Log "Servico SigeDashAgente reiniciado."
}

Log "=== Configuração concluída! ==="
Log "Backend: $BackendUrl | Empresa: $ClienteNome"
Log "Usuarios do Sigecom serao sincronizados automaticamente quando o agente iniciar."
