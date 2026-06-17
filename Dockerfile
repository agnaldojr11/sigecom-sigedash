# ── Stage 1: build ────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore (camada cacheada separada das fontes)
COPY backend/src/SigeDash.Api/SigeDash.Api.csproj SigeDash.Api/
RUN dotnet restore SigeDash.Api/SigeDash.Api.csproj

# Copia fontes + PWA (wwwroot)
COPY backend/src/SigeDash.Api/ SigeDash.Api/
COPY pwa/ SigeDash.Api/wwwroot/

# Publish otimizado
RUN dotnet publish SigeDash.Api/SigeDash.Api.csproj \
    -c Release -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# ── Stage 2: runtime ───────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Porta padrão do ASP.NET Core 8 em containers
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "SigeDash.Api.dll"]
