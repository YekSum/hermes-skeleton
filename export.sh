#!/usr/bin/env bash
# export.sh — keep the public skeleton honest against the live harness.
#
# The repo is a projection, not a snapshot. Three kinds of file:
#
#   copy    verbatim from the live harness. Any difference is a BUILD FAILURE.
#   manual  derived by hand from a live source (SOULs, the checks file, the skill).
#           We cannot regenerate these without inventing prose, so we track the
#           SOURCE hash instead: when the source changes, you get "re-port needed".
#   own     authored in this repo only. Nothing to compare.
#
# Usage:
#   ./export.sh --check    # drift report; exits 1 on copy drift or a re-port need
#   ./export.sh --write    # refresh copy files, stage → sanitize → install
#   ./export.sh --accept   # record current source hashes after a manual re-port
#   ./export.sh --list     # show the manifest and each file's status
#
# Never writes a manual or own file. Never writes anything the sanitizer rejects.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
MANIFEST="$HERE/export.manifest"
LOCK="$HERE/.export-lock"
PATTERNS="$HERE/.sanitize-patterns"

MODE="${1:---check}"

sha() { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1 || echo "missing"; }

# ── read manifest: class <TAB> repo_path <TAB> live_path ────────────────────
declare -a C=() R=() L=()
while IFS=$'\t' read -r cls repo live; do
  case "$cls" in ''|'#'*) continue ;; esac
  C+=("$cls"); R+=("$repo"); L+=("${live//\$HERMES_HOME/$HERMES_HOME}")
done < <(grep -vE '^\s*(#|$)' "$MANIFEST")

status_of() { # idx -> "OK" | "DIFF" | "CHANGED" | "MISSING" | "-"
  local i="$1" cls="${C[$1]}" repo="${R[$1]}" live="${L[$1]}"
  local repo_sha live_sha
  repo_sha="$(sha "$HERE/$repo")"; live_sha="$(sha "$live")"
  case "$cls" in
    copy)
      [ "$repo_sha" = "missing" ] && { echo "MISSING"; return; }
      [ "$live_sha" = "missing" ] && { echo "MISSING"; return; }
      [ "$repo_sha" = "$live_sha" ] && echo "OK" || echo "DIFF" ;;
    manual)
      [ "$(sha "$HERE/$repo")" = "missing" ] && { echo "MISSING"; return; }
      local rec; rec="$(awk -F'\t' -v k="$repo" '$2==k{print $1}' "$LOCK" 2>/dev/null)"
      [ -z "$rec" ] && { echo "UNTRACKED"; return; }
      [ "$rec" = "$live_sha" ] && echo "OK" || echo "CHANGED" ;;
    own) echo "-" ;;
    *) echo "?" ;;
  esac
}

case "$MODE" in
  --list|--check)
    rc=0
    printf '%-8s %-9s %s\n' "CLASS" "STATUS" "PATH"
    for i in "${!C[@]}"; do
      st="$(status_of "$i")"
      printf '%-8s %-9s %s\n' "${C[$i]}" "$st" "${R[$i]}"
      case "$st" in
        DIFF|MISSING) [ "${C[$i]}" = "copy" ] && rc=1 ;;
        CHANGED|UNTRACKED) [ "${C[$i]}" = "manual" ] && rc=1 ;;
      esac
    done
    if [ "$MODE" = "--check" ]; then
      echo
      [ "$rc" = 0 ] && echo "✓ in sync" || echo "✗ drift — fix with --write (copy) or re-port + --accept (manual)"
      exit "$rc"
    fi
    ;;

  --write)
    STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
    n=0
    for i in "${!C[@]}"; do
      [ "${C[$i]}" = "copy" ] || continue
      src="${L[$i]}"
      [ -f "$src" ] || { echo "skip (no source): ${R[$i]}"; continue; }
      mkdir -p "$STAGE/$(dirname "${R[$i]}")"
      cp "$src" "$STAGE/${R[$i]}"
      n=$((n+1))
    done

    # Gate BEFORE anything lands: if the staged content trips the publication bar,
    # nothing is written at all.
    if grep -rniEf "$PATTERNS" "$STAGE" 2>/dev/null | grep -v '/\.git/'; then
      echo
      echo "✗ REFUSING TO WRITE — staged content matches the publication bar (above)."
      echo "  Nothing was changed. Fix the source or add the pattern deliberately."
      exit 2
    fi

    # Re-materialise the tree, then verify the whole repo, not just the staged files.
    ( cd "$STAGE" && find . -type f -print0 | while IFS= read -r -d '' f; do
        mkdir -p "$HERE/$(dirname "$f")"; cp "$f" "$HERE/$f"
      done )
    # Scan only what this repo would actually publish: tracked files plus untracked ones that
    # .gitignore does NOT exclude. A blanket `grep -r` over the tree also reads the FETCHED
    # third-party binaries (surfaces/windows/webview2/, gitignored by design) and a binary can
    # match a text pattern by accident -- which refused every export on a machine that had run
    # the fetch step, with no way to tell that the "violation" was a DLL.
    if ( cd "$HERE" && git ls-files --cached --others --exclude-standard -z \
         | grep -zv '\.sanitize-patterns$' | grep -zv '__pycache__' \
         | xargs -0 -r grep -niEf "$PATTERNS" ) 2>/dev/null; then
      echo "✗ the tree now trips the publication bar — inspect before committing"
      exit 2
    fi
    echo "✓ wrote $n copy file(s); tree passes the publication bar"
    ;;

  --accept)
    # Refuse to record hashes of files that do not exist. A stale HERMES_HOME in the shell (a trial
    # run, a second profile) silently turned every source into "missing", and the lock was rewritten
    # with hashes of nothing — which is worse than no lock, because it looks like a review happened.
    missing=0
    for i in "${!C[@]}"; do
      [ "${C[$i]}" = "own" ] && continue
      [ -f "${L[$i]}" ] || { echo "✗ live source missing for ${R[$i]}: ${L[$i]}"; missing=1; }
    done
    if [ "$missing" = "1" ]; then
      echo
      echo "✗ refusing to write the lock. HERMES_HOME is currently: $HERMES_HOME"
      echo "  Unless that is deliberate, unset it and re-run."
      exit 2
    fi
    [ -f "$LOCK" ] && cp "$LOCK" "$LOCK.bak"
    : > "$LOCK"
    for i in "${!C[@]}"; do
      [ "${C[$i]}" = "manual" ] || continue
      printf '%s\t%s\n' "$(sha "${L[$i]}")" "${R[$i]}" >> "$LOCK"
    done
    echo "✓ recorded $(grep -c . "$LOCK") manual source hash(es) in .export-lock (repo-relative, no machine paths)"
    ;;

  *) echo "unknown mode: $MODE (use --check|--write|--accept|--list)" >&2; exit 2 ;;
esac
