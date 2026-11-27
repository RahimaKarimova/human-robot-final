@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Play-Reachy-Study.ps1" -Resume %*
echo.
pause
