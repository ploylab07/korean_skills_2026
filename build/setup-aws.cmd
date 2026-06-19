@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-aws.ps1"
exit /b %ERRORLEVEL%
