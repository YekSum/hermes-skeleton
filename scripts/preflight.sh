#!/usr/bin/env bash
# preflight.sh — is this machine able to run Hermes, and is Hermes already here?
#
# The first run of a "lazy pack" must not stop at "Hermes not installed, go read the docs". It must
# either install it or explain, in one screen, exactly what is missing and what to do.
#
# What is actually checked, and why nothing more:
#   platform   Linux or WSL. macOS is refused on purpose (untested, and a half-working install is worse
#              than a clear no). Windows-native is not a target at all.
#   prereqs    git, curl, bash 4+. The official installer acquires uv, Python and tool binaries itself,
#              so checking for those would only produce false alarms.
#   disk       ~3 GB. Hermes plus a browser bundle is comfortably under 2 GB; the margin is for updates.
#   network    github.com reachable. If it is not, the install fails four minutes in with a git error,
#              and the user has no idea that the cause was the link rather than the product.
#   hermes     present and answering --version.
#
# Usage:
#   bash scripts/preflight.sh            # check, offer to install if missing (interactive)
#   bash scripts/preflight.sh --check    # report only, never installs
#   bash scripts/preflight.sh --install  # install without asking (for start.cmd / CI)
set -uo pipefail

INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"
MODE="ask"
for a in "$@"; do
  case "$a" in
    --check)   MODE="check" ;;
    --install) MODE="install" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  esac
done

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; }
say()  { printf '\n%s\n' "$*"; }

PROBLEMS=0

# ── platform ────────────────────────────────────────────────────────────────
say "Preflight"
OS="$(uname -s)"
case "$OS" in
  Linux)
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
      ok "platform: WSL on Windows (the supported path for the guide window)"
    else
      ok "platform: Linux (terminal only — there is no window surface here)"
    fi
    ;;
  Darwin)
    bad "platform: macOS is not supported yet."
    echo "        The installer works, but nothing in this repo has been run on it, and"
    echo "        a half-working first run is worse than a clear no. See docs/JOURNEY.md."
    exit 1
    ;;
  *)
    bad "platform: $OS is not a target. This harness is bash + POSIX paths."
    exit 1
    ;;
esac

# ── prerequisites ───────────────────────────────────────────────────────────
for bin in git curl; do
  if command -v "$bin" >/dev/null 2>&1; then ok "$bin present"; else
    bad "$bin is missing — the installer needs it."
    case "$OS" in
      Linux) echo "        sudo apt-get update && sudo apt-get install -y $bin" ;;
    esac
    PROBLEMS=$((PROBLEMS+1))
  fi
done
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then ok "bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"; else
  bad "bash 4+ required (found ${BASH_VERSION:-unknown})"; PROBLEMS=$((PROBLEMS+1))
fi

# ── disk ────────────────────────────────────────────────────────────────────
FREE_GB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{printf "%d", $4/1048576}')"
if [ -n "${FREE_GB:-}" ]; then
  if [ "$FREE_GB" -ge 3 ]; then ok "disk: ${FREE_GB} GB free in \$HOME"; else
    bad "disk: only ${FREE_GB} GB free in \$HOME — the install needs about 3 GB."
    PROBLEMS=$((PROBLEMS+1))
  fi
fi

# ── network ─────────────────────────────────────────────────────────────────
if curl -sI -m 12 https://github.com >/dev/null 2>&1; then ok "github.com reachable"; else
  warn "github.com not reachable (or very slow) right now."
  echo "        The install will fail four minutes in with a git error that looks unrelated."
  echo "        Try a different network, or see the retry advice below when it fails."
  PROBLEMS=$((PROBLEMS+1))
fi

# ── is Hermes here? ─────────────────────────────────────────────────────────
HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
if [ -n "$HERMES_BIN" ] && "$HERMES_BIN" --version >/dev/null 2>&1; then
  ok "hermes: $("$HERMES_BIN" --version 2>/dev/null | head -1)"
  [ "$PROBLEMS" -eq 0 ] || { echo; echo "  Preflight finished with warnings — continuing."; }
  exit 0
fi

# ── missing: install, or explain ────────────────────────────────────────────
bad "hermes is not installed (or not on PATH)."
echo
echo "  The official installer clones Hermes to ~/.hermes/hermes-agent, acquires uv"
echo "  and Python, and publishes the command. It takes a few minutes."
echo
echo "    curl -fsSL $INSTALL_URL | bash"
echo

if [ "$MODE" = "check" ]; then
  echo "  Run without --check to install it, or run the command above yourself."
  exit 1
fi

if [ "$MODE" = "ask" ] && [ -t 0 ]; then
  printf '  Install it now? [Y/n] '
  read -r reply
  case "${reply:-y}" in
    [Nn]*) echo "  Not installed. Nothing else was changed."; exit 1 ;;
  esac
fi

say "Installing Hermes (this is the long step — output below is from the installer)"
# The installer is path-independent and resumes over an existing ~/.hermes/hermes-agent checkout, which
# is why a retry after a network failure usually finishes rather than starting from zero.
if curl -fsSL "$INSTALL_URL" | bash; then
  :
else
  bad "the installer did not finish."
  echo
  echo "  If the last lines were 'RPC failed', 'HTTP 408' or 'promisor remote', the"
  echo "  clone lost the connection — not a problem with this machine. In order:"
  echo "    1. re-run this script; an existing checkout resumes rather than re-cloning"
  echo "    2. git config --global http.version HTTP/1.1    (chunked transfer is the usual cause)"
  echo "    3. git config --global http.postBuffer 524288000"
  echo "    4. if it still fails, clone in full and let the installer adopt it:"
  echo "         git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent"
  echo "       then run this script again"
  echo
  echo "  Full log: ~/.hermes/logs/install.log"
  exit 1
fi

# bash hashes commands; a fresh binary in the same directory is not visible without this
hash -r 2>/dev/null || true
if command -v hermes >/dev/null 2>&1 && hermes --version >/dev/null 2>&1; then
  ok "hermes installed: $(hermes --version 2>/dev/null | head -1)"
  exit 0
fi

bad "the installer finished but 'hermes' is still not on PATH."
echo "  Open a new terminal, or check:  ls ~/.local/bin/hermes"
exit 1
