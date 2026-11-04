#!/usr/bin/env bash
# weekly-drift-check.sh — deterministic harness drift check. No LLM, no network, no secrets.
#
# Reads claims from $HERMES_HOME/ecosystem-map.checks.yaml and runs the command that proves each one.
# Prints a one-line summary every time it runs, so a scheduled job that fires but finds nothing wrong
# is still visibly alive (an empty stdout would be indistinguishable from a job that never ran).
#
# Install:
#   cp weekly-drift-check.sh "$HERMES_HOME/scripts/"
#   hermes cron create "0 9 * * 1" --name "Weekly drift check" \
#       --script weekly-drift-check.sh --deliver local --no-agent
#
# --no-agent = stdout is delivered verbatim, zero tokens. Upgrade to an agent job only when you want
# the drift interpreted rather than merely reported (see weekly-drift-check.job.md).

set -uo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CHECKER="$HERMES_HOME/scripts/map_check.py"

# Fail LOUD. A monitor that prints nothing when it is broken is worse than no monitor: silence is
# exactly what "healthy" looks like.
if [ ! -f "$CHECKER" ]; then
  echo "CHECKER-ERROR: map_check.py not found at $CHECKER — the schedule fired but the checker is missing."
  exit 2
fi

if [ ! -f "$HERMES_HOME/ecosystem-map.checks.yaml" ]; then
  echo "CHECKER-ERROR: no checks file at $HERMES_HOME/ecosystem-map.checks.yaml — nothing to verify."
  exit 2
fi

out="$(python3 "$CHECKER" --verbose 2>&1)"
rc=$?

# Drift lines are the only thing worth reading at a glance; keep them, plus the summary.
drift="$(printf '%s\n' "$out" | grep -E '^DRIFT|^CHECKER-ERROR' || true)"
summary="$(printf '%s\n' "$out" | grep -E '^summary:' | tail -1)"

if [ "$rc" -ne 0 ] || [ -n "$drift" ]; then
  echo "Harness drift — $(date '+%Y-%m-%d %H:%M %Z')"
  printf '%s\n' "$drift"
  [ -n "$summary" ] && printf '%s\n' "$summary"
  echo "Full report: HERMES_HOME=$HERMES_HOME python3 $CHECKER --verbose"
  exit 1
fi

echo "Harness clean — $(date '+%Y-%m-%d %H:%M %Z')${summary:+ · ${summary}}"
exit 0
