@echo off
chcp 65001 >nul
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0empress-name-restore.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Failed. Right-click empress-name-restore.ps1 and select "Run with PowerShell".
    echo.
    pause
)
