@echo off
"%~dp0build\verify.cmd" %*
exit /b %ERRORLEVEL%
