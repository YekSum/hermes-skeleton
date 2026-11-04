# Hermes Ecosystem Skeleton

An **exoskeleton** for a multi-profile Hermes Agent setup: the architecture, the
conventions, and the verification tooling — with **no private context**.

Take this repo to another machine, run one script, and you get the same shape:
an orchestrator profile plus specialists, a single-writer registry/board, a
delegation topology, a documented harness map, and a deterministic checker.

## Schedule the drift check

The checker only helps if something runs it. One command, and it runs weekly for free:

```bash
cp cron/weekly-drift-check.sh "$HERMES_HOME/scripts/" && chmod +x "$HERMES_HOME/scripts/weekly-drift-check.sh"
hermes cron create "0 9 * * 1" --name "Weekly drift check" \
  --script weekly-drift-check.sh --deliver local --no-agent
```

`--no-agent` means stdout is delivered verbatim with no model call: a healthy week costs nothing and
prints one line. Details, the upgrade path to an interpreted report, and why this ships as a spec
rather than an exported job: [`cron/weekly-drift-check.job.md`](cron/weekly-drift-check.job.md).

## Getting started (designed, not yet built)

The intended path is written up in **[`docs/JOURNEY.md`](docs/JOURNEY.md)**: `git clone` → one script to
set the provider key and model → one command to open the interview → a green `map_check` → a first real
task → optionally the desktop app.

It is a design document, not a feature. Today the working path is `./bootstrap.sh --dry-run`, then
without the flag, then fill in `ecosystem-map.md` and each profile's `Personalize` block by hand.

## What ships

| Path | What it is |
|---|---|
| `profiles/<name>/SOUL.md` | Each profile's identity and standing rules |
| `profiles/<name>/distribution.yaml` | Per-profile manifest (so a single profile is installable on its own) |
| `skills/hermes-ecosystem-ops/` | The operating manual: board conventions, delegation guardrails, memory hygiene, the profiles-vs-skills rubric |
| `map/ecosystem-map.template.md` | The "README for Hermes" — structure to fill in for your machine |
| `map/ecosystem-map.checks.yaml` | Claims paired with the commands that prove them |
| `map/scripts/map_check.py` | The deterministic, no-LLM checker |
| `bootstrap.sh` | Creates the profiles, wires delegation, installs the skill |
| `.env.template` | Which credentials each profile needs |
| `SANITIZE.md` | Exactly what was stripped from the source setup, and why |
| `cron/weekly-drift-check.sh` | Deterministic weekly drift check — no LLM, zero tokens |
| `cron/weekly-drift-check.job.md` | The job **spec** (install it yourself; nothing writes your `jobs.json`) |
| `registry/` | Board/project schema, empty templates, and the inbox contract |
| `docs/JOURNEY.md` | The intended onboarding journey — design, not yet built |

## What deliberately does NOT ship

Private context is excluded by design — and the exclusion list is the same one
Hermes itself uses for profile distributions:

```
memories/  sessions/  workspace/  plans/  home/  backups/  cache/  local/
+ any credential store, at any depth
```

So **no `MEMORY.md`, no `USER.md`, no session history, no registry contents, no
research memos, no API keys.** See `SANITIZE.md` for the full account.

## Install

```bash
git clone <this-repo> ~/hermes-ecosystem-skeleton
cd ~/hermes-ecosystem-skeleton
./bootstrap.sh --dry-run     # show what it would do
./bootstrap.sh               # do it
```

Then fill in credentials:

```bash
cp .env.template ~/.hermes/.env        # default/orchestrator profile
# and one per specialist profile, e.g.:
cp .env.template ~/.hermes/profiles/research-engineer/.env
```

`bootstrap.sh` is **non-destructive**: it creates missing profiles, never
overwrites an existing `SOUL.md` without `--force`, and never touches
`memories/`, `workspace/`, or `.env`.

## Verify

```bash
python3 map/scripts/map_check.py --verbose
```

Fill in `map/ecosystem-map.checks.yaml` with the claims that matter for *your*
machine, then wire the checker into a scheduled job so mechanical drift is caught
for free. See the `hermes-ecosystem-ops` skill for the design rules (fail loud,
pin the profile, a DRIFT can mean the check is wrong).

## A note on scope

A Hermes *profile distribution* ships **one profile**. This repo ships an
**ecosystem** — several profiles plus the topology that connects them and the
documentation that explains it. That's a different artifact, assembled here from
the same primitives.

## Design principle

Everything here is **subtraction-friendly**: profiles are the isolation boundary,
memory stays thin, and knowledge lives where it belongs — SOUL for behaviour,
skills for procedure, the map for structure, artifacts for output. Read the
`hermes-ecosystem-ops` skill first; it explains *why* each convention exists,
including the failures that produced them.

## Keeping this repo true to a live harness

`export.sh` regenerates what can be generated and refuses to publish what should not be:

```bash
./export.sh --check     # drift report (CI / pre-commit gate)
./export.sh --write     # refresh files copied from the live harness
./export.sh --accept    # after hand-porting a SOUL / the skill, record the new source hash
cp hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

See `SHIPPING.md` for the rule that decides what belongs here at all: structure travels, biography
does not.
