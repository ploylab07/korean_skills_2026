@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0terraform.ps1" %*
exit /b %ERRORLEVEL%
