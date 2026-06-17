@echo off
title SigeDash — Build Instalador do Agente
setlocal

:: ── Configurações ────────────────────────────────────────────────────────────
set ROOT=%~dp0..\..
set AGENTE_PROJ=%ROOT%\agente\SigeDash.Agente\SigeDash.Agente.csproj
set BIN_OUT=%~dp0bin
set DIST_OUT=%ROOT%\dist

:: Caminho padrão do Inno Setup 6 (ajuste se instalou em local diferente)
set ISCC="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

echo.
echo ============================================================
echo  SigeDash — Build do Instalador do Agente
echo ============================================================
echo.

:: ── 1. Verifica pré-requisitos ───────────────────────────────────────────────
where dotnet >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: .NET SDK nao encontrado. Instale em https://dot.net
    pause & exit /b 1
)

if not exist %ISCC% (
    echo ERRO: Inno Setup 6 nao encontrado em:
    echo   %ISCC%
    echo Baixe em https://jrsoftware.org/isinfo.php
    pause & exit /b 1
)

:: ── 2. Limpa saída anterior ──────────────────────────────────────────────────
echo [1/4] Limpando saida anterior...
if exist "%BIN_OUT%" rd /s /q "%BIN_OUT%"
if exist "%DIST_OUT%" rd /s /q "%DIST_OUT%"
mkdir "%DIST_OUT%"

:: ── 3. Compila agente em Release x64 ────────────────────────────────────────
echo [2/4] Compilando agente (Release x64)...
dotnet publish "%AGENTE_PROJ%" ^
    -c Release ^
    -r win-x64 ^
    --self-contained false ^
    -o "%BIN_OUT%" ^
    -p:DebugType=None ^
    -p:DebugSymbols=false

if %errorlevel% neq 0 (
    echo ERRO: Falha na compilacao do agente.
    pause & exit /b 1
)
echo    OK — binarios em: %BIN_OUT%

:: ── 4. Gera o instalador com Inno Setup ─────────────────────────────────────
echo [3/4] Gerando instalador com Inno Setup...
%ISCC% "%~dp0instalar-agente.iss"

if %errorlevel% neq 0 (
    echo ERRO: Falha ao gerar o instalador.
    pause & exit /b 1
)

:: ── 5. Resultado ─────────────────────────────────────────────────────────────
echo [4/4] Concluido!
echo.
echo Instalador gerado em:
dir /b "%DIST_OUT%\SigeDashAgente-Setup-*.exe" 2>nul | findstr /i "Setup" > nul
if %errorlevel% equ 0 (
    for %%f in ("%DIST_OUT%\SigeDashAgente-Setup-*.exe") do echo   %%f
) else (
    echo   %DIST_OUT%\
)
echo.
pause
