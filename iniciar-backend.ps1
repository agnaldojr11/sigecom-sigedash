$env:ASPNETCORE_ENVIRONMENT = 'Development'
$proj = Join-Path $PSScriptRoot "backend\src\SigeDash.Api\SigeDash.Api.csproj"
Write-Host "Projeto: $proj" -ForegroundColor Cyan
Write-Host "Iniciando backend..." -ForegroundColor Cyan
dotnet run --project $proj
Write-Host ""
Write-Host "Backend encerrado. Pressione qualquer tecla para fechar." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
