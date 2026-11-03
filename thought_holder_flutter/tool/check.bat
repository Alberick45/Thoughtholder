@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0check.ps1"
exit /b %ERRORLEVEL%
