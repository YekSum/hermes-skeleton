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
echo   Five steps. Step 1 may install Hermes (a few minutes, once).
echo   Step 2 asks for an API key. Nothing is installed globally.
echo  ===========================================================
echo.

REM ---------- 1. find a WSL distro ----------
echo  [1/5] Looking for Ubuntu inside WSL...
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

REM If this folder lives INSIDE the WSL filesystem, Explorer opens it as a UNC path
REM (\\wsl.localhost\Ubuntu\home\... or the older \\wsl$\...). wslpath cannot translate those, which
REM is why double-clicking from the WSL home used to fail with "could not map this folder".
set "P=%~dp0"
if /i "!P:~0,16!"=="\\wsl.localhost\" (
    set "REST=!P:~16!"
    for /f "tokens=1,* delims=\" %%a in ("!REST!") do (
        set "DISTRO=%%a"
        set "REPO=/%%b"
    )
    set "REPO=!REPO:\=/!"
    echo        ok - WSL path %REPO%
) else if /i "!P:~0,6!"=="\\wsl$\" (
    set "REST=!P:~6!"
    for /f "tokens=1,* delims=\" %%a in ("!REST!") do (
        set "DISTRO=%%a"
        set "REPO=/%%b"
    )
    set "REPO=!REPO:\=/!"
    echo        ok - WSL path %REPO%
) else (
    for /f "delims=" %%i in ('wsl.exe -d %DISTRO% wslpath -u "%~dp0" 2^>nul') do set "REPO=%%i"
    if defined REPO echo        ok - repo seen from WSL as %REPO%
)
if not defined REPO (
    echo        X Could not work out the WSL path for this folder.
    echo          If the repo is inside WSL, run these two commands in Ubuntu instead:
    echo              cd ~/hermes-skeleton ^&^& ./setup.sh ^&^& ./bootstrap.sh --no-launch
    pause
    exit /b 1
)
echo        ok - repo seen from WSL as %REPO%
echo.

REM ---------- 2. check / install Hermes ----------
echo  [2/5] Checking Hermes (installs it on first run)...
echo.
wsl.exe -d %DISTRO% --cd "%REPO%" -- bash -lc "bash scripts/preflight.sh --install"
if errorlevel 1 (
    echo.
    echo        X Hermes is not installed and could not be installed.
    echo          The reason is in the lines above, with the recovery steps.
    pause
    exit /b 1
)
echo.

REM ---------- 3. provider + key ----------
echo  [3/5] Provider and API key.
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
echo  [4/5] Creating profiles, wiring delegation, installing the guide...
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
echo  [5/5] Starting the guide window...
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
