@echo off
REM One-click deploy: env check + pick assignment + terraform apply
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\start.ps1" %*
exit /b %ERRORLEVEL%
