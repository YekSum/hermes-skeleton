# End-to-end launch test: the logon path must start exactly ONE note, and a second
# launch must not add a second window.
function Count-Note { @(Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "Board" }).Count }

Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "Board" } | Stop-Process -Force
Start-Sleep -Seconds 2
Write-Output ("before: {0} note window(s)" -f (Count-Note))

$cmd = Join-Path $env:LOCALAPPDATA "hermes-board-note\start.cmd"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$cmd`"" -WindowStyle Hidden
Start-Sleep -Seconds 10
$first = Count-Note
Write-Output ("after first launch: {0}" -f $first)

Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$cmd`"" -WindowStyle Hidden
Start-Sleep -Seconds 8
$second = Count-Note
Write-Output ("after second launch: {0}" -f $second)

if ($first -eq 1 -and $second -eq 1) { Write-Output "PASS: exactly one note window" }
else { Write-Output "FAIL: expected exactly 1 after each launch" }
