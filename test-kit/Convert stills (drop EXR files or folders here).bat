@echo off
rem Drop .exr files or folders of stills onto this file.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-ExrToTiff.ps1" %*
echo.
pause
