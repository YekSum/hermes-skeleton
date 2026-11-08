#!/usr/bin/env bash
# bootstrap.sh — install this ecosystem skeleton into a Hermes home.
#
# NON-DESTRUCTIVE BY DEFAULT:
#   * creates only profiles that do not already exist
#   * never overwrites an existing SOUL.md unless --force
#   * never touches memories/, workspace/, sessions/, or .env
#   * never sets a model for you (that's your choice, not this script's)
#
# Usage:
#   ./bootstrap.sh --dry-run     # show every action, change nothing
#   ./bootstrap.sh               # apply
#   ./bootstrap.sh --force       # also overwrite existing SOUL.md files
#   ./bootstrap.sh --no-launch   # never start the guide (CI, piped runs, scripting)
#
# On a real TTY it ends by starting the onboarding guide, so cloning the repo and running
# one command lands the user in a conversation rather than in a wall of instructions.
#
# Env:
#   HERMES_HOME   (default: ~/.hermes)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

DRY_RUN=0
FORCE=0
NO_LAUNCH=0
GUIDE_PROFILE="${GUIDE_PROFILE:-guide}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Specialists that receive delegated work. Keep this list in sync with
# profiles/ and with the delegation routes below.
SPECIALISTS=(project-manager playground-manager reporting-agent health-check-doctor research-engineer coder)

# install_soul <src> <dst> — install a profile SOUL without clobbering a customized one.
# `hermes profile create` writes its OWN stock SOUL.md (the generic Hermes identity). Treating any
# existing file as "the user's" meant the skeleton's SOULs were never installed at all — caught by
# bootstrapping into an empty HERMES_HOME. Stock is replaced (with a backup); customized is kept.
STOCK_MARK='You are Hermes Agent, built by Nous Research. Be direct: match the length'
install_soul() {
  local src="$1" dst="$2" name
  name="$(basename "$(dirname "$dst")")"; [ "$name" = "$HERMES_HOME" ] && name="default"
  if [ ! -f "$dst" ]; then
    run "mkdir -p '$(dirname "$dst")' && cp '$src' '$dst'"
    PERSONALIZE_TODO="${PERSONALIZE_TODO:-} $dst"
    return
  fi
  if [ "$FORCE" = "1" ]; then
    run "cp '$src' '$dst'"
    PERSONALIZE_TODO="${PERSONALIZE_TODO:-} $dst"
    return
  fi
  if grep -qF "$STOCK_MARK" "$dst" 2>/dev/null && ! grep -q "SKELETON TEMPLATE" "$dst" 2>/dev/null; then
    echo "  $name: replacing the stock Hermes SOUL (backup kept as SOUL.md.stock-*)"
    run "cp '$dst' '$dst.stock-$(date +%Y%m%d-%H%M%S)' && cp '$src' '$dst'"
    PERSONALIZE_TODO="${PERSONALIZE_TODO:-} $dst"
  else
    echo "  $name: SOUL.md is customized — leaving it alone (--force to replace)"
  fi
}

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '  [dry-run] %s\n' "$*"
  else
    printf '  %s\n' "$*"
    eval "$@"
  fi
}

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if ! command -v hermes >/dev/null 2>&1; then
  echo "ERROR: 'hermes' not found on PATH. Install Hermes first." >&2
  exit 1
fi

say "Hermes home: $HERMES_HOME"
[ "$DRY_RUN" = "1" ] && echo "(dry run — nothing will be changed)"

# ── 1. The orchestrator (default profile) ────────────────────────────────────
say "1. Orchestrator (default profile)"
install_soul "$HERE/profiles/default/SOUL.md" "$HERMES_HOME/SOUL.md"

# ── 2. Specialist profiles ───────────────────────────────────────────────────
say "2. Specialist profiles"
for p in "${SPECIALISTS[@]}"; do
  if [ -d "$HERMES_HOME/profiles/$p" ]; then
    echo "  $p: exists"
  else
    run "hermes profile create '$p'"
  fi
  install_soul "$HERE/profiles/$p/SOUL.md" "$HERMES_HOME/profiles/$p/SOUL.md"
done

# ── 2b. The onboarding guide ─────────────────────────────────────────────────
# Deliberately NOT in SPECIALISTS: it is not a delegated work target. It is the thing that talks to
# the user, so it must not appear in the routing table as "do this work".
say "2b. Onboarding guide"
if [ -d "$HERMES_HOME/profiles/$GUIDE_PROFILE" ]; then
  echo "  $GUIDE_PROFILE: exists"
else
  run "hermes profile create '$GUIDE_PROFILE'"
fi
install_soul "$HERE/profiles/$GUIDE_PROFILE/SOUL.md" "$HERMES_HOME/profiles/$GUIDE_PROFILE/SOUL.md"
if [ -d "$HERE/profiles/$GUIDE_PROFILE/skills" ]; then
  run "mkdir -p '$HERMES_HOME/profiles/$GUIDE_PROFILE/skills' && cp -r '$HERE/profiles/$GUIDE_PROFILE/skills/.' '$HERMES_HOME/profiles/$GUIDE_PROFILE/skills/'"
fi

# The guide runs with HERMES_HOME=<its own profile home>, so "$HERMES_HOME/memories/USER.md" is ITS
# file, not the user's. Give it an unambiguous pointer by name; a trial run wrote preferences into
# profiles/guide/USER.md, where nothing will ever read them.
GUIDE_ENV="$HERMES_HOME/profiles/$GUIDE_PROFILE/.env"
if [ "$DRY_RUN" != "1" ]; then
  mkdir -p "$(dirname "$GUIDE_ENV")"; touch "$GUIDE_ENV"; chmod 600 "$GUIDE_ENV"
  grep -q '^ECOSYSTEM_ROOT=' "$GUIDE_ENV" 2>/dev/null \
    && sed -i "s|^ECOSYSTEM_ROOT=.*|ECOSYSTEM_ROOT=$HERMES_HOME|" "$GUIDE_ENV" \
    || printf 'ECOSYSTEM_ROOT=%s\n' "$HERMES_HOME" >> "$GUIDE_ENV"
  echo "  guide: ecosystem root recorded in its .env"
else
  echo "  [dry-run] would record ECOSYSTEM_ROOT=$HERMES_HOME in the guide's .env"
fi

# ── 3. Wire delegation ───────────────────────────────────────────────────────
say "3. Delegation topology (profile_routes)"
ROUTES_JSON='['
for p in "${SPECIALISTS[@]}"; do
  ROUTES_JSON+="{\"name\":\"$p\",\"description\":\"specialist profile\"},"
done
ROUTES_JSON="${ROUTES_JSON%,}]"

run "hermes -p default config set delegation.backend profile_routes"
run "hermes -p default config set delegation.backends.profile_routes.profiles '$ROUTES_JSON'"

# ── 4. The operating skill ───────────────────────────────────────────────────
say "4. Operating skill (hermes-ecosystem-ops)"
run "mkdir -p '$HERMES_HOME/skills' && cp -r '$HERE/skills/hermes-ecosystem-ops' '$HERMES_HOME/skills/'"

# ── 5. The map, its checks, and the checker ──────────────────────────────────
say "5. Ecosystem map + deterministic checker"
if [ -f "$HERMES_HOME/ecosystem-map.md" ] && [ "$FORCE" != "1" ]; then
  echo "  ecosystem-map.md exists — leaving it alone (use --force to replace)"
else
  run "cp '$HERE/map/ecosystem-map.template.md' '$HERMES_HOME/ecosystem-map.md'"
fi
if [ -f "$HERMES_HOME/ecosystem-map.checks.yaml" ] && [ "$FORCE" != "1" ]; then
  echo "  ecosystem-map.checks.yaml exists — leaving it alone"
else
  run "cp '$HERE/map/ecosystem-map.checks.yaml' '$HERMES_HOME/ecosystem-map.checks.yaml'"
fi
run "mkdir -p '$HERMES_HOME/scripts' && cp '$HERE/map/scripts/map_check.py' '$HERMES_HOME/scripts/map_check.py'"
run "cp '$HERE/scripts/handover.sh' '$HERMES_HOME/scripts/handover.sh' && chmod +x '$HERMES_HOME/scripts/handover.sh'"

# ── 6. Credentials ───────────────────────────────────────────────────────────
say "6. Credentials (you must fill these in)"
for p in "" "${SPECIALISTS[@]}" "$GUIDE_PROFILE"; do
  target="$HERMES_HOME/.env"
  [ -n "$p" ] && target="$HERMES_HOME/profiles/$p/.env"
  if [ -f "$target" ]; then
    echo "  $(basename "$(dirname "$target")")/.env exists — leaving it alone"
  else
    run "cp '$HERE/.env.template' '$target'"
  fi
done

# ── Done ─────────────────────────────────────────────────────────────────────
say "Done"
# ── Personalize reminder ─────────────────────────────────────────────────────
if [ -n "${PERSONALIZE_TODO:-}" ]; then
  echo
  echo "⚠  These SOULs still contain their 'Personalize — required before use' block."
  echo "   This skeleton ships empty of territory on purpose: rules, not your projects."
  echo "   Fill each one in, then delete the block:"
  for f in $PERSONALIZE_TODO; do
    grep -q "Personalize — required before use" "$f" 2>/dev/null && echo "     $f"
  done
fi

# ── 8. Hand over to the guide ────────────────────────────────────────────────
# The point of the whole script: one command, then a conversation. Everything above is
# plumbing the user should not have to think about.
say "8. Onboarding guide"

# The point of the whole script: one command, then a conversation.
GUIDE_READY=1
GUIDE_SKIP=""
if [ "$DRY_RUN" = "1" ]; then
  GUIDE_READY=0; GUIDE_SKIP="[dry-run] would start: hermes -p $GUIDE_PROFILE chat -q hi"
elif [ "$NO_LAUNCH" = "1" ]; then
  GUIDE_READY=0; GUIDE_SKIP="--no-launch given."
elif [ ! -t 0 ] || [ ! -t 1 ]; then
  GUIDE_READY=0; GUIDE_SKIP="Not a terminal — a piped run must never hang waiting for a conversation."
elif [ ! -d "$HERMES_HOME/profiles/$GUIDE_PROFILE" ]; then
  GUIDE_READY=0; GUIDE_SKIP="No '$GUIDE_PROFILE' profile installed yet, so there is nothing to talk to."
elif ! grep -qE '^[A-Z_]*(_API_KEY|_TOKEN|_KEY)=.+' "$HERMES_HOME/profiles/$GUIDE_PROFILE/.env" 2>/dev/null; then
  # The guide's OWN .env, not the default profile's: profiles do not inherit it. A trial run launched
  # straight into "set OPENROUTER_API_KEY in your environment" because this check accepted the default
  # profile's key — an auth error dressed as a first-run experience is just a bug report.
  GUIDE_READY=0; GUIDE_SKIP="The guide profile has no API key yet — run ./setup.sh (it writes the key to the guide's own .env; profiles do not inherit the default one)."
elif ! hermes -p "$GUIDE_PROFILE" config get model >/dev/null 2>&1; then
  GUIDE_READY=0; GUIDE_SKIP="No model configured for '$GUIDE_PROFILE'."
fi

if [ "$GUIDE_READY" = "1" ]; then
  echo "  Starting the guide — it derives what is still unconfigured from this machine."
  echo
  # Seed the first turn: a model cannot speak unbidden, but the launcher can send one.
  exec hermes -p "$GUIDE_PROFILE" chat -q "hi"
fi

echo "  $GUIDE_SKIP"
echo

# The old tail dumped a six-item operator checklist. For someone who just wants a working assistant that
# read as "nothing happened": no statement that the harness exists, no next step they could act on, and
# no mention that --no-launch leaves the window as the intended first surface.
ON_WSL=0
grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && ON_WSL=1
NP="$(ls -1 "$HERMES_HOME/profiles" 2>/dev/null | wc -l | tr -d ' ')"
KD="$(ls -1 "$HERMES_HOME/profiles/$GUIDE_PROFILE/skills" 2>/dev/null | tr -d '\n' | sed 's/^$/none/')"

echo "────────────────────────────────────────────────────────────────"
echo " Setup finished. What now exists on this machine:"
echo "   profiles   $NP under $HERMES_HOME/profiles"
echo "   map        $HERMES_HOME/ecosystem-map.md  (+ .checks.yaml)"
echo "   checker    $HERMES_HOME/scripts/map_check.py"
echo "   guide      $HERMES_HOME/profiles/$GUIDE_PROFILE  (skills: $KD)"
echo
if [ "$ON_WSL" = "1" ]; then
  echo " What next — the guide window:"
  echo "   Double-click start.cmd in the repo folder, or run:"
  echo "     surfaces\\windows\\run-guide-window.cmd"
  echo "   It opens a bubble near the bottom-right; clicking it starts the conversation."
  echo "   Terminal version, if you prefer:  hermes -p $GUIDE_PROFILE chat -q hi"
else
  echo " What next — start the conversation:"
  echo "   hermes -p $GUIDE_PROFILE chat -q hi"
fi
echo
echo " Not required, but documented in docs/JOURNEY.md (stage 4): personalizing"
echo " each SOUL, per-profile keys, Docker isolation for research, the weekly"
echo " drift check. The harness works without any of it."
echo "────────────────────────────────────────────────────────────────"
