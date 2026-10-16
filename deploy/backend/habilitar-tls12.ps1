<#
.SYNOPSIS
    Habilita o TLS 1.2 no Windows (SChannel + .NET) - necessario em Windows Server 2012/2012 R2
    e 2008 R2 antigos, onde o TLS 1.2 vem desligado por padrao.
.DESCRIPTION
    Sintoma que isto corrige: downloads e chamadas HTTPS (PostgreSQL/EnterpriseDB, GitHub,
    API do Cloudflare) falham com "Nao foi possivel criar um canal seguro para SSL/TLS"
    ("could not create SSL/TLS secure channel"), abortando a instalacao do SigeDash.

    Aplica:
      - .NET Framework: SchUseStrongCrypto + SystemDefaultTlsVersions (x64 e x86)
      - SChannel: habilita o protocolo TLS 1.2 (Client e Server)

    Execute como Administrador e REINICIE o servidor depois. Em seguida rode o instalador de novo.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\habilitar-tls12.ps1
#>
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Execute como Administrador (clique direito -> Executar como administrador)."
    exit 1
}

function SetDword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

Write-Host "Habilitando TLS 1.2 (SChannel + .NET)..." -ForegroundColor Cyan

# 1) .NET Framework usa o TLS do sistema + strong crypto (x64 e WOW64/x86)
foreach ($k in @(
    "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319")) {
    SetDword $k "SchUseStrongCrypto" 1
    SetDword $k "SystemDefaultTlsVersions" 1
}
Write-Host "  .NET: SchUseStrongCrypto + SystemDefaultTlsVersions = 1" -ForegroundColor Green

# 2) SChannel: habilita TLS 1.2 (Client e Server)
$base = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2"
foreach ($lado in @("Client","Server")) {
    SetDword "$base\$lado" "Enabled" 1
    SetDword "$base\$lado" "DisabledByDefault" 0
}
Write-Host "  SChannel: TLS 1.2 Client/Server habilitado" -ForegroundColor Green

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Yellow
Write-Host "  TLS 1.2 habilitado. REINICIE o servidor agora." -ForegroundColor Yellow
Write-Host "  Depois do reboot, rode o instalador do SigeDash de novo." -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Yellow
