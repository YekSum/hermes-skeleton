@echo off
REM run-guide-window.cmd - start the guide window on Windows.
REM
REM Starts guide-bridge.py inside WSL, then opens the floating window. No admin rights needed.
REM Nothing needs editing: start-bridge.ps1 works out the repo path from its own location.

setlocal
set WSL_DISTRO=Ubuntu

echo Starting the bridge in WSL...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-bridge.ps1" -Distro %WSL_DISTRO%
if errorlevel 1 (
    echo.
    echo   The window will still open, but it cannot answer until the bridge is up.
)

echo Opening the window...
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0guide-window.ps1"

endlocal
