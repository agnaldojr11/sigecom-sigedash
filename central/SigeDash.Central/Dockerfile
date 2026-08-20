# SigeDash Central — build + runtime .NET 8 (Railway)
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY SigeDash.Central.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app ./
# Railway injeta PORT em runtime; o Program.cs escuta em 0.0.0.0:$PORT.
EXPOSE 8080
ENTRYPOINT ["dotnet", "SigeDash.Central.dll"]
