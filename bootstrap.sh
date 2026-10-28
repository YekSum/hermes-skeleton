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
#
# Env:
#   HERMES_HOME   (default: ~/.hermes)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

DRY_RUN=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Specialists that receive delegated work. Keep this list in sync with
# profiles/ and with the delegation routes below.
SPECIALISTS=(project-manager playground-manager reporting-agent health-check-doctor research-engineer)

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
if [ -f "$HERMES_HOME/SOUL.md" ] && [ "$FORCE" != "1" ]; then
  echo "  SOUL.md exists — leaving it alone (use --force to replace)"
else
  run "mkdir -p '$HERMES_HOME' && cp '$HERE/profiles/default/SOUL.md' '$HERMES_HOME/SOUL.md'"
fi

# ── 2. Specialist profiles ───────────────────────────────────────────────────
say "2. Specialist profiles"
for p in "${SPECIALISTS[@]}"; do
  if [ -f "$HERMES_HOME/profiles/$p/config.yaml" ]; then
    echo "  $p: exists"
  else
    run "hermes profile create '$p'"
  fi
  if [ -f "$HERMES_HOME/profiles/$p/SOUL.md" ] && [ "$FORCE" != "1" ]; then
    echo "  $p: SOUL.md exists — leaving it alone"
  else
    run "mkdir -p '$HERMES_HOME/profiles/$p' && cp '$HERE/profiles/$p/SOUL.md' '$HERMES_HOME/profiles/$p/SOUL.md'"
  fi
done

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

# ── 6. Credentials ───────────────────────────────────────────────────────────
say "6. Credentials (you must fill these in)"
for p in "" "${SPECIALISTS[@]}"; do
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
cat <<'EOF'
Next steps:

  1. Fill in credentials — each profile gets ONLY the keys it needs:
       $EDITOR "$HERMES_HOME/.env"
       $EDITOR "$HERMES_HOME/profiles/research-engineer/.env"   # etc.

  2. Choose each profile's model (deliberately — the script won't guess):
       hermes -p <profile> config get model.default

  3. Set terminal isolation where you want it:
       hermes -p research-engineer config set terminal.backend docker

  4. Fill in the map and its checks for THIS machine:
       $EDITOR "$HERMES_HOME/ecosystem-map.md"
       $EDITOR "$HERMES_HOME/ecosystem-map.checks.yaml"

  5. Verify the checker works, then wire it into a scheduled job:
       python3 "$HERMES_HOME/scripts/map_check.py" --verbose

  6. Restart the gateway so new skills/plugins are visible to fresh sessions.

Read the hermes-ecosystem-ops skill before changing conventions — it explains
why each one exists, including the failures that produced them.
EOF
