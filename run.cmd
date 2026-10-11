@echo off
setlocal
set "APP_DIR=%~dp0"

where.exe pwsh.exe >nul 2>&1
if errorlevel 1 goto use_windows_powershell

pwsh.exe -NoLogo -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 goto use_windows_powershell

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%menu.ps1"
exit /b %errorlevel%

:use_windows_powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%menu.ps1"
exit /b %errorlevel%
