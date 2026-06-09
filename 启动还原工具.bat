@echo off
chcp 65001 >nul 2>&1
title 女帝篇 - 和谐人名还原工具
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0empress-name-restore.ps1"
pause
