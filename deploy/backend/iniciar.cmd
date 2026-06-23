@echo off
setlocal
title SigeDash - Instalacao

:: Verifica privilegio de Administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  [ERRO] Execute este arquivo como Administrador!
    echo  Clique com o botao direito no arquivo e selecione "Executar como administrador".
    echo.
    pause
    exit /b 1
)

echo.
echo  ============================================================
echo   SigeDash - Instalacao Automatica
echo  ============================================================
echo.
echo  Desbloqueando scripts...
powershell -Command "Get-ChildItem '%~dp0*.ps1' | Unblock-File" >nul 2>&1

echo  Iniciando instalacao...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0instalar-tudo.ps1" %*

echo.
pause
