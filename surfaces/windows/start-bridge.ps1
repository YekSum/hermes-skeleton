<#
    start-bridge.ps1 — start guide-bridge.py in WSL so it outlives this window.

    Why this exists: `wsl.exe -- bash -lc "nohup python3 … &"` does not survive. When the wsl.exe
    session leader exits, WSL tears the session down and the bridge dies a second later — which is why
    the window used to report "Unable to connect" on the first message instead of at launch.

    A detached Windows process keeps its own wsl.exe session alive for as long as the bridge runs.

    Two details that cost real debugging time:
      - Start-Process joins -ArgumentList with spaces, so the payload must be ONE argument string; an
        array mangles the quoted `bash -lc "…"` and wsl.exe silently starts nothing.
      - The string is built with single quotes: inside a double-quoted PS string a backslash is a
        literal, so \" leaks into the bash command line.
#>
param(
    [int]$Port = 8765,
    [string]$Distro = "Ubuntu",
    [string]$Repo = "",
    [int]$WaitSeconds = 30
)

# The repo path is derived from this script's own location. A hardcoded default is how the bridge
# failed silently on every machine whose clone was not called ~/hermes-ecosystem-skeleton: the README
# says ~/hermes-skeleton, so `cd` failed, python never ran, and nothing said so.
function ConvertTo-WslPath {
    param([string]$WinPath, [string]$Distro)
    if ($WinPath -match '^\\\\wsl\.localhost\\([^\\]+)\\(.*)$') { return '/' + ($matches[2] -replace '\\', '/') }
    if ($WinPath -match '^\\\\wsl\$\\([^\\]+)\\(.*)$')         { return '/' + ($matches[2] -replace '\\', '/') }
    try { $out = & wsl.exe -d $Distro wslpath -u $WinPath 2>$null } catch { $out = $null }
    if ($out) { return ($out | Select-Object -First 1).Trim() }
    return $null
}

if (-not $Repo) {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $Repo = ConvertTo-WslPath -WinPath $repoRoot -Distro $Distro
    if (-not $Repo) {
        "       could not work out the WSL path for $repoRoot"
        "       pass it explicitly:  -Repo /home/<you>/hermes-skeleton"
        exit 1
    }
}

$argLine = '-d ' + $Distro + ' -- bash -lc "cd ' + $Repo + ' && exec python3 surfaces/windows/guide-bridge.py --port ' + $Port + ' > /tmp/guide-bridge.log 2>&1"'

$ok = $false
$started = $false
for ($i = 0; $i -lt $WaitSeconds; $i++) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', $Port); $ok = $true } catch { } finally { $c.Close() }
    if ($ok) { break }
    if (-not $started) {
        Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList $argLine
        $started = $true
    }
    Start-Sleep -Milliseconds 1000
}

if ($ok) {
    "       bridge: up on 127.0.0.1:$Port  (repo: $Repo)"
    exit 0
}

"       bridge: FAILED - nothing answered on 127.0.0.1:$Port"
"       In a WSL terminal:  cd $Repo && python3 surfaces/windows/guide-bridge.py"
"       Its output, if it started at all:  cat /tmp/guide-bridge.log"
exit 1
