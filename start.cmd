@echo off
REM =====================================================================
REM  start.cmd - the ONE thing to double-click on Windows.
REM
REM  Runs everything inside WSL, in this window, so you can watch it work.
REM  Do NOT run the .sh files from PowerShell: Windows does not know what a
REM  .sh file is and will ask you to pick an app (Notepad is not it).
REM =====================================================================
setlocal EnableDelayedExpansion
title Hermes skeleton - first run

echo.
echo  ===========================================================
echo   HERMES SKELETON - SETUP
echo   Four steps, about two minutes. You will be asked for an
echo   API key in step 2. Nothing is installed globally.
echo  ===========================================================
echo.

REM ---------- 1. find a WSL distro ----------
echo  [1/4] Looking for Ubuntu inside WSL...
set "DISTRO="
for %%d in (Ubuntu Ubuntu-24.04 Ubuntu-22.04 Ubuntu-20.04) do (
    if not defined DISTRO (
        wsl.exe -d %%d -e true >nul 2>&1 && set "DISTRO=%%d"
    )
)
if not defined DISTRO (
    echo        X No Ubuntu distro found.
    echo.
    echo        Open PowerShell as Administrator and run:
    echo            wsl --install -d Ubuntu
    echo        then reboot and double-click this file again.
    echo.
    pause
    exit /b 1
)
echo        ok - %DISTRO%

for /f "delims=" %%i in ('wsl.exe -d %DISTRO% wslpath -u "%~dp0" 2^>nul') do set "REPO=%%i"
if not defined REPO (
    echo        X Could not map this folder into WSL. Is the repo on a Windows drive?
    pause
    exit /b 1
)
echo        ok - repo seen from WSL as %REPO%
echo.

REM ---------- 2. provider + key ----------
echo  [2/4] Provider and API key.
echo        This verifies the key with a live call before saving it.
echo.
wsl.exe -d %DISTRO% --cd "%REPO%" -- bash -lc "./setup.sh"
if errorlevel 1 (
    echo.
    echo        X Setup did not finish. The reason is in the lines above.
    pause
    exit /b 1
)
echo.
echo        ok - provider and key saved
echo.

REM ---------- 3. profiles ----------
echo  [3/4] Creating profiles, wiring delegation, installing the guide...
echo.
wsl.exe -d %DISTRO% --cd "%REPO%" -- bash -lc "./bootstrap.sh --no-launch"
if errorlevel 1 (
    echo.
    echo        X Bootstrap did not finish. The reason is in the lines above.
    pause
    exit /b 1
)
echo.
echo        ok - harness created
echo.

REM ---------- 4. the window ----------
echo  [4/4] Starting the guide window...
wsl.exe -d %DISTRO% -- bash -lc "cd %REPO% && if ! (ss -ltn 2>/dev/null | grep -q ':8765'); then nohup python3 surfaces/windows/guide-bridge.py > /tmp/guide-bridge.log 2>&1 & sleep 3; fi; ss -ltn 2>/dev/null | grep -q ':8765' && echo '       bridge: up' || echo '       bridge: FAILED - see /tmp/guide-bridge.log'"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0surfaces\windows\guide-window.ps1"

echo.
echo  ===========================================================
echo   DONE.
echo   A blue bubble should be near the bottom-right of your
echo   screen. Click it to talk to the guide.
echo.
echo   If no bubble appeared, right-click this window and read
echo   the PowerShell error: run  surfaces\windows\guide-window.cmd
echo   from a terminal instead of double-clicking it.
echo  ===========================================================
echo.
pause
