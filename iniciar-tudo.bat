@echo off
title SigeDash — Dev Local
setlocal

set ROOT=%~dp0
set PROJ=%ROOT%backend\src\SigeDash.Api\SigeDash.Api.csproj

echo.
echo  ================================================
echo   SigeDash — Ambiente de Desenvolvimento Local
echo  ================================================
echo.

:: ── 1. Verifica PostgreSQL ────────────────────────────────────────────────────
sc query postgresql-x64-17 | findstr "RUNNING" >nul 2>&1
if %errorlevel% equ 0 (
    echo  [OK] PostgreSQL rodando
) else (
    echo  [!!] PostgreSQL NAO esta rodando. Iniciando...
    net start postgresql-x64-17 >nul 2>&1
    timeout /t 2 /nobreak >nul
    sc query postgresql-x64-17 | findstr "RUNNING" >nul 2>&1
    if %errorlevel% neq 0 (
        echo  [ERRO] Nao foi possivel iniciar o PostgreSQL.
        echo         Inicie manualmente: services.msc
        pause & exit /b 1
    )
    echo  [OK] PostgreSQL iniciado
)

:: ── 2. Verifica Firebird ──────────────────────────────────────────────────────
sc query FirebirdServerDefaultInstance | findstr "RUNNING" >nul 2>&1
if %errorlevel% equ 0 (
    echo  [OK] Firebird rodando
) else (
    echo  [AV] Firebird NAO esta rodando (necessario para o agente).
    echo       O backend e o PWA funcionam sem ele.
)

:: ── 3. Verifica agente (servico Windows) ─────────────────────────────────────
sc query SigeDashAgente >nul 2>&1
if %errorlevel% equ 0 (
    sc query SigeDashAgente | findstr "RUNNING" >nul 2>&1
    if %errorlevel% equ 0 (
        echo  [OK] SigeDash Agente (servico) rodando
    ) else (
        echo  [AV] SigeDash Agente (servico) instalado mas parado.
        echo       Para iniciar: sc start SigeDashAgente
    )
) else (
    echo  [--] SigeDash Agente nao instalado como servico.
    echo       Para modo console: iniciar-agente.bat
)

echo.
echo  Subindo backend em http://localhost:5000 ...
echo  (PWA tambem disponivel em http://localhost:5000)
echo.

:: ── 4. Inicia backend via PowerShell (janela fica aberta para ver erros)
start "SigeDash Backend" powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%iniciar-backend.ps1"

:: ── 5. Aguarda o backend subir e abre o browser ──────────────────────────────
echo  Aguardando backend inicializar...
timeout /t 5 /nobreak >nul

:: Tenta abrir no browser padrão
start "" "http://localhost:5000"

echo.
echo  Pronto! Acesse: http://localhost:5000
echo  Esta janela pode ser fechada.
echo.
pause
