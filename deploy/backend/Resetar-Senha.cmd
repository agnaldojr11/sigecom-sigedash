@echo off
title SigeDash - Resetar Senha
REM Atalho clicavel para redefinir a senha de um usuario do SigeDash NESTE servidor.
REM Auto-eleva para Administrador e roda o resetar-senha.ps1 (pergunta o login).

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Solicitando privilegios de administrador...
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

set "PS1=%~dp0resetar-senha.ps1"
if not exist "%PS1%" set "PS1=C:\SigeDash\Backend\resetar-senha.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

echo.
pause
