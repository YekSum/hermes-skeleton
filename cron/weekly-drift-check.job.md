# Weekly drift check — job spec

A **specification**, not a job definition. You install it with one command; nothing writes into your
`jobs.json`.

## Why a spec and not an exported job

- A live job definition carries **per-install state**: job id, delivery target, next-run timestamp. An
  exported job pointed at someone else's channel fails *silently* — the worst failure for a monitor.
- The **prompt is part of the job's code.** Delivery assumptions and report shape live in the stored
  prompt, so a generic "run the health check" prompt produces a generic report. Writing it down is how
  the shape survives.
- A schedule needs a **channel the user has**. If you skipped messaging setup, a delivery-based job has
  nowhere to send. `--deliver local` always works.

## The job

| field | value |
|---|---|
| name | `Weekly drift check` |
| schedule | `0 9 * * 1` — Mondays 09:00 local time |
| script | `weekly-drift-check.sh` (copy to `$HERMES_HOME/scripts/` first) |
| mode | `--no-agent` — stdout delivered verbatim, **zero tokens** |
| deliver | `local` (writes to the job's output dir; change to `telegram` etc. once a channel exists) |
| skills | none needed in script mode |

## Install

```bash
cp cron/weekly-drift-check.sh "$HERMES_HOME/scripts/"
chmod +x "$HERMES_HOME/scripts/weekly-drift-check.sh"

hermes cron create "0 9 * * 1" \
  --name "Weekly drift check" \
  --script weekly-drift-check.sh \
  --deliver local --no-agent
```

Verify it before trusting the schedule — run the script once by hand:

```bash
"$HERMES_HOME/scripts/weekly-drift-check.sh"; echo "exit=$?"
```

Healthy prints one line: `Harness clean — 2026-11-02 09:00 +08 · summary: 66/66 pass, 0 drift`.
Drift prints the drift lines, the summary, and exits 1.

## What it prints

- **Clean:** one line. That is deliberate — a weekly "all good" that costs nothing is what makes a red
  week mean something.
- **Drift:** a header, the `DRIFT` lines only (not the 60 passing checks), the summary, and the command
  to see the full report.
- **Broken:** a `CHECKER-ERROR` line and exit 2. A monitor that goes quiet when it breaks looks exactly
  like a healthy system, so it always says something.

## Upgrading to interpretation

Script mode reports; it does not explain. When a drift needs judgement ("the map says docker, the
machine says local — which is right?"), promote the job to an agent job:

```bash
hermes cron create "0 9 * * 1" --name "Weekly drift check (interpreted)" \
  --script weekly-drift-check.sh --skill hermes-ecosystem-ops --deliver local
```

Now the script's output is injected into the prompt and the agent decides whether it is a doc bug or a
real regression. Costs tokens every week — worth it only while the map is still changing. A useful
middle ground: keep the script job weekly and add `--monitor-script`, which skips the model entirely
when the output is unchanged from last run.

## What this job does not do

- It does not fix anything. Drift is a decision: the claim or the machine is wrong.
- It does not cover claims nobody encoded. Green means "nothing we thought to check has changed", not
  "the map is true".
- It does not replace the map's own drift log. A weekly report is a signal; the log is the record.
