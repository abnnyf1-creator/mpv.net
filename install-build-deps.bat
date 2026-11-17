@echo off
rem mpv.net - one-click build dependency installer (wrapper)
rem Only installs .NET 10 SDK (if missing) and restores NuGet packages.
rem Does NOT build or compile the project.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-build-deps.ps1"
echo.
pause
