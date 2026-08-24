@echo off
REM day3 one-click: check tools -> apply infra -> post-deploy (or destroy)
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" %*
exit /b %ERRORLEVEL%
