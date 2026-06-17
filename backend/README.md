# SigeDash Backend

ASP.NET Core (.NET 8) + PostgreSQL. Roda no VPS.

## Subir local
1. `dotnet restore`
2. Ajustar `appsettings.json` (ConnectionStrings:Postgres e Jwt:SecretKey)
3. `dotnet ef migrations add Inicial && dotnet ef database update`
4. `dotnet run --project src/SigeDash.Api`

## Endpoints
- `POST /ingest/{codigoEmpresa}/{handle}`  — agente envia snapshot (header `X-SigeDash-Key`, corpo gzip JSON)
- `POST /auth/login`                        — login do usuario do app (devolve JWT)
- `GET  /dash/{codigoEmpresa}`              — PWA busca ultimos indicadores (Bearer JWT)

## TODO
- Painel admin de implantacao (substitui admin.plugmobile.com.br)
- Retencao/expurgo de snapshots antigos
- Extrair geradoEm do payload no /ingest
