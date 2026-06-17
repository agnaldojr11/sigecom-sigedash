@echo off
title SigeDash — Backend
set ASPNETCORE_ENVIRONMENT=Development
echo Subindo backend em http://localhost:5000 ...
dotnet run --project backend\src\SigeDash.Api
pause
