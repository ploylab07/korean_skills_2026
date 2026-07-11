@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0add-rule.ps1" %*
exit /b %ERRORLEVEL%
