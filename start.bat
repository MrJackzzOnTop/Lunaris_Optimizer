@echo off
setlocal
title Lunaris Optimizer
cd /d "%~dp0"

if not exist "%~dp0main.ps1" (
    echo [ERROR] main.ps1 not found!
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0main.ps1"

endlocal