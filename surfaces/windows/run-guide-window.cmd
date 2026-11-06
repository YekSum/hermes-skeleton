@echo off
REM run-guide-window.cmd — start the guide window on Windows.
REM
REM It does two things: starts guide-bridge.py inside WSL (if it is not already running), then opens
REM the floating window. Nothing here needs administrator rights.
REM
REM Adjust WSL_DISTRO / WSL_REPO if your setup differs.

setlocal
set WSL_DISTRO=Ubuntu
REM path INSIDE WSL where you cloned the repo (tildes are fine here)
set WSL_REPO=~/hermes-ecosystem-skeleton

echo Starting the bridge in WSL...
wsl.exe -d %WSL_DISTRO% -- bash -lc "if ! ss -ltn 2>/dev/null | grep -q ':8765'; then nohup python3 %WSL_REPO%/surfaces/windows/guide-bridge.py > /tmp/guide-bridge.log 2>&1 & sleep 2; fi; ss -ltn | grep -q ':8765' && echo bridge: up || echo bridge: FAILED (see /tmp/guide-bridge.log)"

echo Opening the window...
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0guide-window.ps1"

endlocal
