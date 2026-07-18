@echo off
REM Windows: Docker Desktop에서 Windows 워크플로 스모크 테스트
setlocal
cd /d "%~dp0..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-windows.ps1" %*
exit /b %ERRORLEVEL%
