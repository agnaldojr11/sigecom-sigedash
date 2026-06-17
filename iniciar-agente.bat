@echo off
title SigeDash — Agente
echo Compilando agente...
dotnet build agente\SigeDash.Agente -c Debug -nologo -v q
echo.
echo Iniciando agente (modo console)...
agente\SigeDash.Agente\bin\Debug\net48\SigeDash.Agente.exe --console
pause
