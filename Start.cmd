@echo off
setlocal
start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0Alcatel.ps1" -Action App
exit /b %errorlevel%
