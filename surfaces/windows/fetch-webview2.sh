#!/usr/bin/env bash
# fetch-webview2.sh — get the WebView2 assemblies the Windows note needs.
#
# They are NOT in this repo on purpose: they are third-party binaries (~1 MB) redistributed
# under Microsoft's terms, and a public skeleton should carry a fetch step, not vendored DLLs.
# Run this once per machine, before the note's first launch.
#
# Why these three files: the WPF/WinForms *controls* are managed assemblies that NuGet ships
# under lib/net462; WebView2Loader.dll is the native shim the control P/Invokes. The WebView2
# RUNTIME itself (the Edge engine) is already on Windows 11 / current Edge — this script does
# not install it, and it can't: check for it with the registry key printed at the end.
#
#   ./fetch-webview2.sh                 # install next to this script (surfaces/windows/webview2)
#   ./fetch-webview2.sh /tmp/wv2        # somewhere else
#
# Idempotent: re-running with the files present and the same version is a no-op.
set -euo pipefail

VERSION="${WEBVIEW2_VERSION:-1.0.4314.35}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HERE/webview2}"

command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v unzip >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || {
  echo "need unzip or python3 to unpack the package"; exit 1; }

WANT=(
  "lib/net462/Microsoft.Web.WebView2.Core.dll"
  "lib/net462/Microsoft.Web.WebView2.WinForms.dll"
  "runtimes/win-x64/native/WebView2Loader.dll"
)
BASE="https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2"
PKG="microsoft.web.webview2.${VERSION}.nupkg"

if [ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ] \
   && [ -f "$DEST/Microsoft.Web.WebView2.WinForms.dll" ]; then
  echo "ok: WebView2 assemblies already present in $DEST (version $VERSION)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "downloading Microsoft.Web.WebView2 $VERSION ..."
curl -fsSL --max-time 180 -o "$TMP/$PKG" "$BASE/$VERSION/$PKG" \
  || { echo "download failed — check the network (and, on WSL, that IPv6 is not black-holing: try curl -4)"; exit 1; }

mkdir -p "$DEST"
extract() {  # <member> <dest-name>
  if command -v unzip >/dev/null 2>&1; then
    unzip -p "$TMP/$PKG" "$1" > "$DEST/$2"
  else
    python3 - "$TMP/$PKG" "$1" "$DEST/$2" <<'PY'
import sys, zipfile, shutil
with zipfile.ZipFile(sys.argv[1]) as z, z.open(sys.argv[2]) as src, open(sys.argv[3], "wb") as dst:
    shutil.copyfileobj(src, dst)
PY
  fi
}
extract "${WANT[0]}" "Microsoft.Web.WebView2.Core.dll"
extract "${WANT[1]}" "Microsoft.Web.WebView2.WinForms.dll"
extract "${WANT[2]}" "WebView2Loader.dll"
printf '%s' "$VERSION" > "$DEST/.version"

echo "installed into $DEST:"
ls -1 "$DEST"
cat <<'EOF'

Verify the WebView2 RUNTIME is present (the assemblies are useless without it):
  powershell.exe -NoProfile -Command "Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' | Select-Object pv"
It ships with Windows 11 and current Edge; if the key is missing, install the WebView2 Runtime
from Microsoft (Evergreen Standalone Installer).

Then check the whole dependency chain before launching a window:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '\\wsl.localhost\<distro>\<path>\board-note.ps1' -ValidateOnly"
EOF
