@echo off
REM One-click deploy: env check + pick assignment + terraform apply
REM Force UTF-8 code page so PowerShell parses scripts correctly on Korean Windows
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\start.ps1" %*
exit /b %ERRORLEVEL%
