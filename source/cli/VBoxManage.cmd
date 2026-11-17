@echo off
setlocal DisableDelayedExpansion
rem Use only the paired adapter beside this file. Never search PATH or CALL.
"%~dp0VBoxManagePortable.exe" %*
exit /b %errorlevel%
