<#
.SYNOPSIS
    Rotaciona os segredos de um SigeDash ja instalado usando CSPRNG (chave JWT + AdminKey).
.DESCRIPTION
    Le o appsettings.Production.json, gera segredos fortes com RandomNumberGenerator (nao Get-Random),
    faz backup, grava e reinicia o servico. Rotacionar a chave JWT DESLOGA todos os usuarios (normal).
    Opcional: -IncluirPostgres troca tambem a senha do usuario 'sigedash' no PostgreSQL (ALTER ROLE)
    e atualiza a connection string.

    Use para "recomeco limpo" de instalacoes cujas chaves foram geradas com PRNG fraco (versoes antigas).
.PARAMETER InstallDir
    Pasta do backend. Padrao: C:\SigeDash\Backend
.PARAMETER IncluirPostgres
    Rotaciona tambem a senha do PostgreSQL do usuario 'sigedash'.
.PARAMETER SemReiniciar
    Nao reinicia o servico ao final.
.EXAMPLE
    .\rotacionar-segredos.ps1
    .\rotacionar-segredos.ps1 -IncluirPostgres
#>
param(
    [string]$InstallDir = "C:\SigeDash\Backend",
    [switch]$IncluirPostgres,
    [switch]$SemReiniciar
)

$ErrorActionPreference = "Stop"
$SVC = "SigeDashBackend"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute este script como Administrador."
    exit 1
}

$appsettings = Join-Path $InstallDir "appsettings.Production.json"
if (-not (Test-Path $appsettings)) { Write-Error "Nao encontrei $appsettings"; exit 1 }

function NovaChave([int]$nbytes) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $b = New-Object byte[] $nbytes; $rng.GetBytes($b)
    return [Convert]::ToBase64String($b)
}

# Backup antes de tocar
$bak = "$appsettings.bak-$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item $appsettings $bak -Force
Write-Host "Backup criado: $bak"

$json = Get-Content $appsettings -Raw | ConvertFrom-Json

# JWT (48 bytes = 384 bits) e AdminKey (32 bytes = 256 bits)
$json.Jwt.SecretKey = NovaChave 48
$novoAdmin          = NovaChave 32
$json.AdminKey      = $novoAdmin
Write-Host "Nova chave JWT e AdminKey geradas (CSPRNG)."

if ($IncluirPostgres) {
    $conn = $json.ConnectionStrings.Postgres
    $kv = @{}
    foreach ($p in ($conn -split ';')) {
        if ($p -match '=') { $k, $v = $p -split '=', 2; $kv[$k.Trim().ToLower()] = $v.Trim() }
    }
    $pgUser = $kv['username']; $pgHost = $kv['host']; $pgDb = $kv['database']
    $pgPort = if ($kv['port']) { $kv['port'] } else { '5432' }
    $pgOld  = $kv['password']

    $novaPg = (NovaChave 24) -replace '[^a-zA-Z0-9]', ''
    $novaPg = ($novaPg + "Sd1!").Substring(0, 16)

    $psql = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
    if (-not $psql) {
        Write-Warning "psql.exe nao encontrado - senha do PostgreSQL NAO rotacionada."
    } else {
        $env:PGPASSWORD = $pgOld
        $tmp = Join-Path $env:TEMP "sigedash_rot.sql"
        Set-Content $tmp "ALTER ROLE `"$pgUser`" WITH PASSWORD '$novaPg';" -Encoding ASCII
        & $psql.FullName -U $pgUser -h $pgHost -p $pgPort -d $pgDb -f $tmp
        Remove-Item $tmp -ErrorAction SilentlyContinue
        $json.ConnectionStrings.Postgres = ($conn -replace 'Password=[^;]*', "Password=$novaPg")
        Write-Host "Senha do PostgreSQL rotacionada e connection string atualizada."
    }
}

# Grava UTF-8 sem BOM (appsettings)
$out = $json | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($appsettings, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host "appsettings.Production.json atualizado."

if (-not $SemReiniciar) {
    Write-Host "Reiniciando $SVC ..."
    Restart-Service $SVC -Force
    Start-Sleep -Seconds 4
    $st = (Get-Service $SVC).Status
    Write-Host "Servico $SVC : $st  (todos os usuarios foram deslogados - comportamento esperado)"
}

Write-Host ""
Write-Host "AdminKey nova (anote; NAO fica salva em log): $novoAdmin" -ForegroundColor Yellow
Write-Host "Concluido. Backup do arquivo anterior em: $bak"
