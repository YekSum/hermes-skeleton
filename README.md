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

## Quickstart

### Windows + WSL — the path with a window

**Double-click `start.cmd`.** It runs everything inside WSL in one window — checking the machine,
installing Hermes if it is missing, provider and key, profiles, checks — then opens the guide as a
floating bubble near the bottom-right of the screen. Five numbered steps, and it stops with a reason if
any step fails.

> **Never run the `.sh` files from PowerShell, and never double-click them.** Windows does not know what
> a `.sh` file is, so it asks you to pick an app to open it with — Notepad is not it. Everything runs
> *inside* WSL. If you see an "How do you want to open this file?" dialog, you are on the wrong side of
> the wall.

Prerequisite: WSL2 with Ubuntu. In an admin PowerShell: `wsl --install -d Ubuntu`, then reboot.

### Ubuntu / Linux — the terminal path

```bash
git clone git@github.com:<owner>/hermes-skeleton.git
cd hermes-skeleton
./setup.sh            # provider + API key (verified with a live call before it is saved)
./bootstrap.sh        # profiles, delegation, map, then the guide conversation
```

### What you should see

| step | what it looks like | time |
|---|---|---|
| preflight | `ok`/`FAIL` lines for platform, git, curl, disk, GitHub, Hermes — and if Hermes is missing it offers to install it, showing the exact command first | 0 s, or 3–5 min on first run |
| setup | a numbered provider list, one key prompt, then `key verified` and the models it can see | ~1 min, one thing to type |
| bootstrap | a numbered section per step, one line per profile created, then a **Setup finished** box listing what now exists and what to do next | ~1 min |
| the guide | a blue bubble bottom-right (Windows) or the first interview question (terminal) | instant |

Nothing here is silent: every step prints what it did, and a failure stops the run instead of leaving
you with a half-configured harness.

**Afterwards**, the full customization checklist — personalizing each SOUL, per-profile keys, Docker
isolation, the weekly drift check — is [`docs/JOURNEY.md`](docs/JOURNEY.md) stage 4. None of it is
required for the harness to work.

## What ships

| Path | What it is |
|---|---|
| `profiles/<name>/SOUL.md` | Each profile's identity and standing rules |
| `profiles/<name>/distribution.yaml` | Per-profile manifest (so a single profile is installable on its own) |
| `profiles/guide/` | The onboarding guide — its SOUL plus the `onboarding-guide` skill (question bank, probes, closing script). Ships **complete**, not as a template: it fills in everyone else's. |
| `skills/hermes-ecosystem-ops/` | The operating manual: board conventions, delegation guardrails, memory hygiene, the profiles-vs-skills rubric |
| `map/ecosystem-map.template.md` | The "README for Hermes" — structure to fill in for your machine |
| `map/ecosystem-map.checks.yaml` | Claims paired with the commands that prove them |
| `map/scripts/map_check.py` | The deterministic, no-LLM checker |
| `start.cmd` | **Windows entry point.** Runs the whole setup inside WSL, then opens the guide window |
| `scripts/preflight.sh` | Is this machine able to run Hermes — and if not, install it. Platform, prereqs, disk, network |
| `setup.sh` | Provider + key, verified before saving. The only place a credential is typed |
| `bootstrap.sh` | Creates the profiles, wires delegation, installs the skill, hands over to the guide |
| `.env.template` | Which credentials each profile needs |
| `SANITIZE.md` | Exactly what was stripped from the source setup, and why |
| `cron/weekly-drift-check.sh` | Deterministic weekly drift check — no LLM, zero tokens |
| `cron/weekly-drift-check.job.md` | The job **spec** (install it yourself; nothing writes your `jobs.json`) |
| `registry/` | Board/project schema, empty templates, and the inbox contract |
| `surfaces/windows/` | The guide window: WPF bubble + WSL bridge (`guide-bridge.py`) |
| `docs/JOURNEY.md` | The onboarding journey: stages, platform matrix, and the answers behind them |

## What deliberately does NOT ship

Private context is excluded by design — and the exclusion list is the same one
Hermes itself uses for profile distributions:

```
memories/  sessions/  workspace/  plans/  home/  backups/  cache/  local/
+ any credential store, at any depth
```

So **no `MEMORY.md`, no `USER.md`, no session history, no registry contents, no
research memos, no API keys.** See `SANITIZE.md` for the full account.

## Platforms and surfaces

One supported setup path per platform. The *guide* is the same everywhere — same questions, same
derived state, same files written. What differs is only the **surface** it runs in, so nothing is
second-class and nothing half-exists.

| Platform | Setup | First-run surface |
|---|---|---|
| **WSL on Windows** | supported | **chat-head window** (extra step, below) or the terminal — both work |
| **Native Linux** (Ubuntu) | supported | **terminal** (default; this is the supported path) |
| **macOS** | not supported yet — the installer refuses | planned, not built |
| **Windows without WSL** | not supported | — |

⚠️ **Windows alone is not a target.** The harness is bash + systemd + POSIX paths; there is no
PowerShell equivalent worth writing for `systemctl --user`, `ss` or the container checks. Install WSL
first — the guide will say the same thing.

### The chat-head window (WSL + Windows only, optional)

Built: [`surfaces/windows/`](surfaces/windows/) — a WPF bubble talking HTTP to a WSL bridge.

A small always-on-top bubble that opens the guide in a window instead of a terminal. It is a **Windows
program** talking to the Linux side, because transparency and always-on-top are exactly what breaks
under WSLg — which is also why the pet overlay in this ecosystem is a Windows program.

- It is **extra setup**, not part of `bootstrap.sh`, and the terminal path never depends on it.
- Closing the panel collapses it to a bubble; it only disappears on an explicit *Quit*.
- Re-open it any time with `guide` in a terminal (the profile wrapper) — the window is a convenience,
  and the terminal is always the fallback.

On native Linux and macOS this surface does not exist yet; those platforms use the terminal guide,
which is the same conversation.

## Install

```bash
git clone <this-repo> ~/hermes-ecosystem-skeleton
cd ~/hermes-ecosystem-skeleton
./setup.sh                   # provider + key + model, verified with one live call
./bootstrap.sh               # profiles, delegation, skill, then the guide starts
```

`./setup.sh` is the only place a credential is typed: input is hidden, it is never echoed or logged,
and it is written straight into `.env` with mode 600. If the key is wrong you find out in twenty
seconds, not two hundred lines into an interview. `./setup.sh --check` reports what is configured
without changing anything.

Everything else needs no keys. A profile gets a credential only if it uses that provider — a profile
that cannot reach a provider cannot silently spend on it.

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
