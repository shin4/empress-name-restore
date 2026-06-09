@echo off
chcp 65001 >nul
if not exist "%~dp0empress-name-restore.ps1" (
    echo.
    echo ============================================
    echo   ERROR: empress-name-restore.ps1 not found
    echo ============================================
    echo.
    echo   You must EXTRACT the ZIP first, then run
    echo   this .bat from the extracted folder.
    echo.
    echo   Do NOT run directly from inside the ZIP.
    echo.
    pause
    exit /b 1
)
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0empress-name-restore.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Script failed. Right-click empress-name-restore.ps1 and select "Run with PowerShell".
    echo.
    pause
)
