@echo off
setlocal
echo Reinstalling ThoughtHolder on your PC...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_to_pc.ps1"
pause

