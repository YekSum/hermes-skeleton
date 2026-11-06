#!/usr/bin/env bash
# handover.sh — move what the guide learned into the user's own memory.
#
# Why this exists: the guide is a profile, and a profile's memory belongs to that profile. When the
# guide saves "the user prefers short answers", the `memory` tool writes it to
# profiles/guide/memories/USER.md — where nothing outside the guide will ever read it. The user's own
# preferences live one level up, at <ecosystem>/memories/USER.md.
#
# So the guide's memory is a STAGING AREA, and this is the hand-over: merge what it holds into the
# user's file, keep their existing entries intact, never duplicate a line, and archive a backup first.
#
# Usage:  bash handover.sh            # merge, report what moved
#         bash handover.sh --dry-run  # show what would move, change nothing
set -uo pipefail

# When the guide runs this, HERMES_HOME is the guide's own profile, so the ecosystem root has to come
# from the variable bootstrap wrote into its .env.
ROOT="${ECOSYSTEM_ROOT:-${HERMES_HOME:-$HOME/.hermes}}"
GUIDE="${GUIDE_PROFILE:-guide}"
SRC="$ROOT/profiles/$GUIDE/memories/USER.md"
DST="$ROOT/memories/USER.md"
ARCHIVE="$ROOT/memories/archive"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

[ -f "$SRC" ] || { echo "nothing to hand over — $SRC does not exist"; exit 0; }
mkdir -p "$(dirname "$DST")"

# entries are separated by a line containing only §
mapfile -t SRC_ENTRIES < <(awk 'BEGIN{RS="\n§\n"} {gsub(/^\s+|\s+$/,""); if(length($0)) print}' "$SRC")
[ -f "$DST" ] && mapfile -t DST_ENTRIES < <(awk 'BEGIN{RS="\n§\n"} {gsub(/^\s+|\s+$/,""); if(length($0)) print}' "$DST")

moved=0; skipped=0; NEW=()
for e in "${SRC_ENTRIES[@]:-}"; do
  [ -z "${e:-}" ] && continue
  dup=0
  for d in "${DST_ENTRIES[@]:-}"; do [ "$e" = "$d" ] && { dup=1; break; }; done
  if [ "$dup" = "1" ]; then skipped=$((skipped+1)); else NEW+=("$e"); moved=$((moved+1)); fi
done

if [ "$moved" = "0" ]; then
  echo "nothing new to hand over ($skipped already in $DST)"
  exit 0
fi

if [ "$DRY" = "1" ]; then
  echo "[dry-run] would add $moved entr(y/ies) to $DST:"
  printf '  · %s\n' "${NEW[@]}"
  exit 0
fi

mkdir -p "$ARCHIVE"
[ -f "$DST" ] && cp "$DST" "$ARCHIVE/USER-$(date +%Y%m%d-%H%M%S).md"

for e in "${NEW[@]}"; do
  # keep the § separator discipline the memory file uses
  [ -s "$DST" ] && printf '\n§\n' >> "$DST"
  printf '%s\n' "$e" >> "$DST"
done

# the guide keeps its copy, but marks it as handed over so a re-run is honest about the state
mv "$SRC" "$SRC.handed-over-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

echo "✓ handed over $moved entr(y/ies) to $DST ($skipped already present)"
echo "  backup: $ARCHIVE/"
