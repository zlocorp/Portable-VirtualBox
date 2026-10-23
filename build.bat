@echo off
rem Compatibility entrypoint for the ACTIVE Windows x64 diagnostic build.
rem Neither 7-Zip nor any bundled AutoIt/compiler or historical installer is used.
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 goto WindowsPowerShell
pwsh.exe -NoProfile -File "%~dp0scripts\build.ps1" %*
exit /b %errorlevel%
:WindowsPowerShell
powershell.exe -NoProfile -File "%~dp0scripts\build.ps1" %*
exit /b %errorlevel%
