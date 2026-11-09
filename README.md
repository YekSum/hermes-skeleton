# Hermes Ecosystem Skeleton

An **exoskeleton** for a multi-profile Hermes Agent setup: the architecture, the conventions, and the
verification tooling — with **no private context**.

Clone it, run one thing, and you get the same shape: an orchestrator profile plus specialists, a
single-writer registry/board, a delegation topology, a documented harness map, and a deterministic
checker that proves the map is still true. Then an onboarding guide walks you through the rest.

---

## What you need

| | |
|---|---|
| **Platform** | Windows with WSL2 + Ubuntu, or Ubuntu/Debian itself |
| **Disk** | ~3 GB free (Hermes, Python, tool binaries) |
| **Network** | Working DNS — `curl -sI https://github.com` should answer |
| **Model** | An API key (OpenRouter / OpenAI / Anthropic / Google) **or** a local endpoint |

macOS is **not supported yet** — the installer refuses rather than half-works. Windows without WSL is
not a target: this harness is bash + systemd + POSIX paths.

---

## Step 1 — Get the repo

Clone it **inside WSL**, not from PowerShell:

```bash
git clone <owner>/hermes-skeleton.git ~/hermes-skeleton
cd ~/hermes-skeleton
```

---

## Step 2 — Run the setup

### On Windows + WSL

**Double-click `start.cmd`** in the repo folder. That's the whole step.

It opens a console, does everything below inside WSL so you can watch it, and stays open at the end.

> **Never double-click a `.sh` file on Windows.** Windows has no association for them and will ask
> which app should open it — Notepad is not the answer. Either use `start.cmd`, or run the commands
> inside an Ubuntu terminal.

### On Ubuntu / Linux

```bash
./setup.sh        # provider, key, model — the only place you type a credential
./bootstrap.sh    # profiles, delegation, skill, map, then the guide starts
```

### What those steps do

| # | Step | What happens | Time |
|---|---|---|---|
| 1 | `start.cmd` finds WSL | probes the distro, maps the repo path into it | instant |
| 2 | `preflight.sh` | checks platform, git/curl, disk, GitHub; **installs Hermes if missing** | 3–5 min first time |
| 3 | `setup.sh` | provider menu → paste key (hidden) → **verified with a live call** → model chosen from the provider's list | ~1 min |
| 4 | `bootstrap.sh` | creates profiles, wires delegation, installs skill + map + checker | ~1 min |
| 5 | the window | starts the bridge, opens the guide bubble | instant |

Steps 3–4 are skipped on later runs: `setup.sh` reports "Already configured" and `bootstrap.sh` never
overwrites existing files.

---

## Step 3 — Talk to the guide

- **Windows:** a blue bubble appears near the bottom-right. Click it.
- **Linux:** the interview starts in your terminal.

It asks your name, what you want to work on, which specialists you want, and which model to use — one
question at a time. Then it writes the map for *this* machine, runs the check, and reports what you have.

**Reopening later:**

| | |
|---|---|
| Windows | double-click `start.cmd` again, or run `surfaces\windows\run-guide-window.cmd` |
| Any terminal | `hermes -p guide chat -q hi` |

Closing the panel collapses the bubble to a head; right-click it to quit.

---

## What success looks like

| Step | You should see |
|---|---|
| `preflight.sh` | `ok` lines for platform, git, curl, disk, GitHub, Hermes |
| `setup.sh` | `key accepted (HTTP 200)` and a numbered model list |
| `bootstrap.sh` | one line per profile, then a **Setup finished** box listing profiles, map, checker, guide |
| the window | `bridge: up`, then a bubble; clicking it produces the first interview question |
| the guide's close | `✓ N/N checks pass — 0 drift` and a short list of what you now have |

Nothing here is silent. Every step prints what it did, and a failure stops the run with a reason
instead of leaving you half-configured.

---

## If something fails

| Symptom | Cause | Do this |
|---|---|---|
| "Windows wants an app to open this file" | you ran a `.sh` from Windows | use `start.cmd`, or run inside WSL |
| `hermes: command not found` | Hermes not installed / not on PATH | `bash scripts/preflight.sh` — it offers to install |
| `RPC failed; HTTP 408` on clone | partial clone losing the connection | clone in full, see below |
| `Temporary failure in name resolution`, PyPI timeouts | DNS, or a broken IPv6 route | test `curl -4 https://files.pythonhosted.org/`; prefer IPv4 |
| `bridge error` in the window | the bridge isn't running | `curl http://127.0.0.1:8765/health` in WSL |
| bubble missing entirely | a PowerShell error, hidden by `-WindowStyle Hidden` | run `surfaces\windows\guide-window.ps1` from a terminal |

**For the git 408 specifically** — the installer uses a partial clone (file contents fetched on demand),
which a flaky link cannot finish. Clone it in full, then let the installer adopt the checkout:

```bash
rm -rf ~/.hermes/hermes-agent
git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

---

## After setup — optional, safe to ignore

- **Verify anything, any time:** `python3 "$HERMES_HOME/scripts/map_check.py" --verbose`
- **Personalize the profiles:** each `SOUL.md` ships with rules but no territory. That gap is
  deliberate — fill it from use, not from a template.
- **Schedule the drift check** — ran weekly, zero tokens:

  ```bash
  cp cron/weekly-drift-check.sh "$HERMES_HOME/scripts/" && chmod +x "$HERMES_HOME/scripts/weekly-drift-check.sh"
  hermes cron create "0 9 * * 1" --name "Weekly drift check" \
    --script weekly-drift-check.sh --deliver local --no-agent
  ```

- **The full checklist** — per-profile keys, Docker isolation, gateway, desktop app: `docs/JOURNEY.md`
  stage 4.

---

## Platforms and surfaces

The guide is the same everywhere: same questions, same derived state, same files. Only the **surface**
differs.

| Platform | Setup | First-run surface |
|---|---|---|
| **WSL on Windows** | supported | chat-head window, or terminal |
| **Native Linux** (Ubuntu) | supported | terminal |
| **macOS** | not supported yet — refused | planned |
| **Windows without WSL** | not supported | — |

### The chat-head window (WSL + Windows only)

[`surfaces/windows/`](surfaces/windows/) — a WPF bubble talking HTTP to a bridge in WSL
(`guide-bridge.py`). It is a Windows program talking to the Linux side because transparency and
always-on-top are exactly what WSLg breaks. It is **extra, never required**: the terminal guide is the
same conversation.

---

## What ships

| Path | What it is |
|---|---|
| `start.cmd` | **Windows entry point** — runs the whole setup inside WSL, then opens the window |
| `scripts/preflight.sh` | Can this machine run Hermes — and if not, installs it |
| `setup.sh` | Provider + key, verified before saving. The only place a credential is typed |
| `bootstrap.sh` | Profiles, delegation, skill, map, then the guide |
| `profiles/<name>/SOUL.md` | Each profile's identity and standing rules |
| `profiles/guide/` | The onboarding guide — SOUL + `onboarding-guide` skill. Ships **complete**: it fills in everyone else's |
| `skills/hermes-ecosystem-ops/` | The operating manual: board conventions, delegation guardrails, memory hygiene |
| `map/` | The harness map template, its checks, and the deterministic checker |
| `registry/` | Board/project schema, empty templates, the inbox contract |
| `surfaces/windows/` | The guide window: bubble + bridge |
| `cron/` | The weekly drift check — script and job spec |
| `docs/JOURNEY.md` | The onboarding design: stages, platform matrix, open questions |
| `SANITIZE.md` | Exactly what was stripped from the source setup, and why |

## What deliberately does NOT ship

```
memories/  sessions/  workspace/  plans/  home/  backups/  cache/  local/
+ any credential store, at any depth
```

No `MEMORY.md`, no `USER.md`, no session history, no registry contents, no API keys. A skeleton that
arrives pre-filled is just someone else's habits — see `SANITIZE.md`.

---

## Keeping this repo true to a live harness

```bash
./export.sh --check     # drift report (CI / pre-commit gate)
./export.sh --write     # refresh files copied from the live harness
./export.sh --accept    # after hand-porting a SOUL / the skill, record the new source hash
cp hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

`SHIPPING.md` holds the rule that decides what belongs here: **structure travels, biography does not.**
