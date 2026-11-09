@echo off
:: Board note - a desktop sticky note showing the Hermes Kanban board.
:: Double-click this file. It opens the Windows window that reads the live viewer in WSL.
setlocal
set "HERE=%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& '%HERE%board-note.ps1' %*"
endlocal
