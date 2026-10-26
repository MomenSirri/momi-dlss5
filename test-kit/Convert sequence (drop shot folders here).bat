@echo off
rem Drop one or more folders of EXR frames onto this file. Each folder becomes one movie at 25 fps.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-ExrToTiff.ps1" -Sequence %*
echo.
pause
