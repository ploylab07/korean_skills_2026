@echo off
"%~dp0build\terraform.cmd" %*
exit /b %ERRORLEVEL%
