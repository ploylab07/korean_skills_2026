@echo off
REM 단일 진입점: 환경 준비 + 과제 선택 + Terraform 자동화
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\start.ps1" %*
exit /b %ERRORLEVEL%
