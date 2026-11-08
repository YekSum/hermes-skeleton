# Onboarding journey — zero to green

**Status:** draft, not implemented. Board item HA-023. Gates HA-018 / HA-021 (pick one to build),
and feeds RP-008.
**Platform:** **Ubuntu / WSL first.** macOS is explicitly out of scope until the Linux path is boring;
the installer must *say so and stop*, not half-work.

The **README carries the compatibility matrix** (WSL+Windows → bubble or terminal; native Linux →
terminal; macOS → refused, planned; Windows without WSL → not a target). This file designs the path, not
the surface matrix; when they disagree, the README wins because it is what a newcomer reads first.

The platform is **detected, not asked**: `uname -s` plus `grep -qi microsoft /proc/version` separates
native Linux, WSL-on-Windows and macOS before the first question, and the guide confirms it in the same
breath ("I can see you're on WSL — right?"). WSL is the only platform where the desktop surfaces exist,
so it is worth naming explicitly. Pure Windows is not a target: the harness is bash + systemd + POSIX
paths, and those are not opinions the skeleton can compromise on.

---

## The one problem that decides the whole shape

**The interview cannot run before a model is configured.** The interviewer is an agent; an agent needs
a provider and a key. So the first stage can contain no conversation at all — it must be a plain
script, because at that moment there is nothing to talk to yet.

That is why stage 1 is a shell/python step and stage 2 is the chat. Everything else follows from it.

---

## How the assistant speaks first

A model never speaks unbidden — it answers. But the *user* does not have to type first, because the
launcher can send the opening turn on their behalf:

```bash
hermes -p onboarding chat -q "hi"          # seeds the interactive session, then stays interactive
```

`-q` on a real TTY submits the text as the first turn and drops into the normal interactive session.
So the sequence the user experiences is: run one command → the assistant greets them and asks its first
question → they reply. The single `hi` in the transcript is the cost of not needing a custom TUI.

Design notes:

- **Seed the shortest possible token** (`hi`, or `BEGIN_SETUP` if you prefer it machine-readable). The
  profile's SOUL recognises it and opens with the introduction. A long seed prompt would appear in the
  transcript and read like the user was told what to ask.
- **The profile must exist before the launcher runs.** Stage 1 creates it (`hermes profile create
  onboarding`, copy the SOUL into place) — the installer installs the interviewer. That is also why the
  interview can use a model the user just configured: same `.env`, same `config.yaml`.
- **Never a custom TUI for this.** A launcher that prints its own greeting and then hands over produces
  two voices in one session; let the agent own the conversation.

## One command, then a conversation

```bash
git clone <repo> && cd <repo> && ./bootstrap.sh
```

That is the whole entry point. `bootstrap.sh` creates the profiles, wires delegation, installs the
skill, and — on a real terminal — **ends by starting the guide**, so the first thing the user meets is a
conversation, not a wall of instructions. Stages 0–2 below are what that one command does, in order;
they are separated here because each has its own failure modes, not because the user runs three
commands.

Guards on the hand-over, each learned from a way it goes wrong:

- **Never launch on a non-TTY** (`[ -t 0 ]`). A piped or CI run would hang forever waiting for a
  conversation nobody can see.
- **`--no-launch`** for scripted installs, and `--dry-run` never launches at all.
- **Missing prerequisites are reported, not entered into.** No `guide` profile or no model configured
  prints the exact command to fix it rather than opening a session that cannot answer.
- **Re-running is safe.** Bootstrap is non-destructive; if the guide is already set up it says so and
  offers what is left, because its state is derived (see "The tutorial model").

## Stage 0 — prerequisites (README, copy-paste only)

**Windows users start here:** double-click `start.cmd` instead of running the scripts by hand. Windows
does not associate `.sh` files, so double-clicking one opens an "how do you want to open this file?"
dialog — and PowerShell is the wrong shell for them too. `start.cmd` resolves the WSL distro, runs both
scripts inside WSL in a visible window, then opens the guide window.

Two things must already be true, and the README says them in two lines:

1. Hermes Agent is installed and `hermes --version` works.
2. You are on Ubuntu or WSL. On anything else the next command refuses and explains.

No judgement calls, no profiling, nothing to read beyond the two lines.

## Stage 1 — `./setup.sh` — key, model, no LLM  ✅ built

One command. It asks the smallest possible set of questions, in plain text:

```
Which provider?    [1] OpenRouter  [2] Anthropic  [3] Google  [4] I have a local endpoint
Paste your key:    (input hidden, never echoed, never printed, never logged)
Which model?       (a short list per provider, with a cheap one recommended)
```

Then it:

- writes `.env` for the profiles that need it (names only in the repo; values only here),
- **verifies the key with one live call** — a failure is a clear message, not a stack trace,
- writes the chosen model into `config.yaml` for the default profile,
- **creates the onboarding profile itself** (`hermes profile create onboarding` + its SOUL), so the
  next command has something to talk to,
- prints exactly one thing on success: `✓ model reachable — starting the interview`.

Design rules for this stage:

- **Never echo or log the key.** No `set -x`, no writing it into a log file, no "your key is sk-…xyz".
- **Verifiable, not assumed.** A wrong key must fail here, not 200 lines into the interview.
- **Idempotent.** Running it twice changes nothing and asks nothing already answered. `--check` mode
  reports state without writing.
- **No secrets in the repo, ever.** This script writes to `.env`; it never writes to a tracked file.

## Stage 2 — the interview (launched by `bootstrap.sh`)  ✅ built

One command opens a chat session with the onboarding prompt. This is the first moment the skeleton
introduces itself, and the order of the conversation matters more than the wording:

1. **Name first.** "I'm your assistant — what should I call myself?" Cheap, personal, and it makes the
   rest of the conversation feel like a relationship rather than a wizard.
2. **Introduce the skeleton in plain language**, before asking for anything. What a profile is, why
   there are several, what the board is for, how memory works (standing orders in `MEMORY.md`, facts
   in the map, a short brief generated at every session start). Two short paragraphs — no jargon dump.
   A user who does not understand the shape cannot answer questions about it.
   The introduction must name **delegation** explicitly, because it is the part people do not expect:
   work is routed to a specialist profile that has its own model, its own credentials and its own
   sandbox, and every delegation leaves a transcript. That is the difference between "one assistant"
   and "a team with an audit trail" — and it is invisible until someone explains it.
3. **Intent.** "What do you actually want to work on?" — free text, no options. This is where their
   preferences start forming, and it is what later writes into `USER.md`.
4. **Scope**, as a small set of concrete choices derived from the answer, not a menu of everything:
   do you want a project registry? research help? a builder? a health checker? Install only what they
   said yes to (`HA-018`'s core idea: do not dump the full ecosystem on them).
5. **Personalize.** Fill the `## Personalize` blocks in the chosen profiles from their answers, then
   delete the blocks. This is the interview script — it already exists in every SOUL.

Rules that keep it from becoming an interrogation:

- **≤ 8 questions, one at a time, always skippable** with a stated default.
- **Every answer is written somewhere specific** (a SOUL block, `USER.md`, a board row) — never "kept
  in the conversation". If it is not written, the next session has to ask again.
- **Never invent an answer to fill a gap.** Unanswered → default, and say which default was used.
- **Resumable.** Quit halfway and the next run picks up at the first unanswered question.
- **No secrets in the chat.** Provider setup is stage 1, in a terminal, never in the transcript.

## Stage 3 — prove it: `map_check` goes green

The interview ends by running the deterministic checker and fixing what it reports, out loud:

```
✓ 66/66 checks pass — 0 drift
```

This is the closing ritual, and it matters more than it looks: it is the first time the user sees the
system *test itself*, and it is the moment "done" becomes verifiable rather than claimed. The checker
already knows what is unconfigured on a fresh machine — that is how the skeleton's own missing-SOULs
bug was caught.

If checks fail: fix, or mark the claim as intentionally deferred in the map. Never end on a red check
with an apology.

## Stage 4 — day two: the first real thing

Setup is not finished until one loop has been run end to end. Three small tasks, in the chat:

1. **File one board item** — something they actually want. (Registry: created by use, not by reading.)
2. **Run one delegation** — the smallest possible task to a specialist. (Delegation topology: same.)
3. **Drop one inbox note** — and watch the steward merge it. (Single-writer: same.)

Ten minutes. Without this the mechanisms are theory, and the second session starts from zero.

## Stage 5 — optional: where do you talk to it?

The harness works in a terminal. Everything here is an add-on, offered once, at the end, skippable —
and **run from a script, never from the chat**, because both surfaces need a credential.

**5a. Messaging (Telegram, Discord, WhatsApp…).** The best fit for most people: the assistant reaches
them where they already are, and the desktop becomes unnecessary.

- The token is created *outside* — BotFather for Telegram, a developer app for Discord. The script
  prints the three steps with links and waits.
- ⚠️ **The token must never be typed into the chat.** Session transcripts are stored; a token pasted
  into a conversation is a credential in a database. The script reads it with hidden input, writes it
  to the profile `.env`, and never prints it back.
- **Ask who is allowed to talk to the bot** (allowed users / channels) before enabling it. A bot with
  open access is a remote control for the machine.
- Verify, do not assume: send one message from the allowed account, receive one reply, then report the
  result. Then note that the gateway multiplexes profiles, so one bot can serve several.

**5b. The desktop app.** Last, and genuinely optional.

- It is a **client**, not part of the harness — the ecosystem is verified and working without it.
- It adds failure surface: a serve service, a session token, and on WSL a Windows-side install. That is
  a bad thing to put in front of someone who has not yet seen anything work.
- It gives the journey a finish: *"setup is done and verified — open the app and say hello."*

## Stage 6 — a rhythm (schedule the drift check)

Setup is verified on day one. The thing that kills it later is silent drift: a provider changes a key
format, a plugin stops loading, a profile's backend flips to docker. Nobody notices, because nothing
runs. The skeleton ships the checker (`map_check.py`) and the checks file; it should also ship **the
schedule**, or the check only ever runs when someone remembers.

**Ship the job's design and its script, never a live job definition.** Three reasons, all learned the
hard way:

- **A job definition carries per-install state** — job id, delivery target, next-run timestamp. Ours
  had a Telegram channel baked in. Imported into a fresh install it delivers to a chat that does not
  exist and fails *quietly*, which is the worst possible failure for a monitor.
- **The prompt is part of the job's code.** Format instructions and delivery assumptions live in the
  stored prompt; a generic "run the health check" prompt produces a generic report. Ship the text.
- **A schedule needs a channel the user has.** If the user skipped stage 5, a delivery-based job has
  nowhere to send. Default the spec to `deliver: none` (write to the output dir) and let the user
  point it somewhere in one edit.

So the deliverable is a `cron/` folder: `weekly-drift-check.sh` (deterministic, `map_check.py
--summary`, no LLM, no personal paths) plus `weekly-drift-check.job.md` — a human-readable spec giving
name, schedule, script, skills, and the report shape — and one install command in the README
(`hermes cron add ...`). The user runs it; we never write into their `jobs.json` directly.

**The honest caveat:** the deterministic part is free and safe to schedule. The LLM pass on top costs
tokens every week and is only worth it while the map is still changing. Recommend the script-only job
as the default and mention the agent variant as an upgrade — a weekly zero-token "healthy" line is
still worth having, and it makes a red week meaningful.

**If you move the desktop earlier** — offered as the interview's own surface — it goes between stages 1
and 2, never inside stage 1, and you accept a doubled first-run failure rate in exchange for a nicer
conversation.

---

## The tutorial model — must-setup, then optional

The guide is not a wizard that runs once and dies. It is closer to an open-world tutorial: it stays
available, insists on the things that must work, and then gets out of the way.

**Two tiers.**

- **Must-setup** (the guide will not let go): a model and key that provably work; the profiles the user
  chose created; `ecosystem-map.md` present; `map_check` green. Until these pass, the harness is not
  running — it is merely installed.
- **Optional, always offered, never nagged**: messaging, the desktop app, the weekly schedule, a second
  specialist, the first delegation, a knowledge store. Once must-setup is green the guide says so
  plainly — *"you can stop here"* — and lists what is left without tracking it as failure.

**Progress is derived, never remembered.** The guide answers "where am I?" by probing the system, not
by reading its own notes:

| question | probe |
|---|---|
| model configured and working? | one live call, or the config + a cheap request |
| profiles created? | `profiles/<name>/config.yaml` exists |
| map written? | `ecosystem-map.md` exists and is not the template |
| verified? | `map_check.py` exit code |
| messaging on? | the gateway unit is enabled and a platform key exists in `.env` |
| anything scheduled? | a job in `hermes cron list` referencing the drift script |

This is the same rule as the session brief: a hand-written status goes stale, a derived one cannot.
It also means the guide works on a machine that was set up months ago by someone else — it re-derives
instead of assuming it remembers.

**Consequence: the guide keeps no state file.** Its memory is the system. If it cannot derive a fact,
it should ask, not assume.

**Why a profile and not a skill.** By the rubric a profile earns its existence on model, credentials,
isolation or lifecycle — and this one earns it on lifecycle: it recurs, with continuity, across
sessions and machines. Everything else about it (its wording, its question list) belongs in a skill so
it can be updated without touching a profile home.

**Naming:** if it persists, `onboarding` is a misnomer — its job outlives setup. `guide` is honest.

---

## Open questions

- **Where does the onboarding agent run?** In the default profile (which exists on a fresh install), or
  as a throwaway profile that deletes itself? The former is simpler; the latter keeps the user's first
  profile clean of setup chatter. *Revised 2026-11-02: a dedicated `guide` profile — installed in
  stage 1, used in stage 2, and **kept**. It persists as a tutorial guide whose must-setup tier it will
  not let go of, and whose progress is derived from the system rather than remembered. See "The
  tutorial model" above.*
- **Does the interview create profiles via `bootstrap.sh`, or write them itself?** Reusing bootstrap
  keeps one implementation of profile creation; it also means the interview must handle bootstrap's
  refusals.
- **How is the interview shipped?** *Decided 2026-11-02: a **profile** (`guide`), launched automatically
  by `bootstrap.sh` — HA-018, not HA-021.* The requirement that settled it: after `git clone` and one
  command, the profile must be running and asking the right questions. A profile also earns its
  existence on lifecycle (it recurs), which a CLI wrapper does not. HA-021 stays on the board as the
  alternative mechanism, unbuilt. **Remaining artifact: the `guide` profile's SOUL** — the question
  list, the must-setup probes, and the introduction. The launch path is in place and tested; there is
  simply nothing for it to open yet.
- **Which messaging platform is the default recommendation?** Telegram is the cheapest to set up
  (BotFather, one token, no app review); Discord needs a developer app; WhatsApp needs a business
  account. Pick one to lead with and mention the others.
- **Does the onboarding profile persist after setup?** It costs a profile home and a slot in the routing
  table, and its job is over. Either document it as "delete when done" or give it a second duty
  (re-running setup on a new machine). *Reversed 2026-11-02: it **does** persist — deleting it removes
  the one thing that answers "how do I…?" three weeks later, at exactly the moment that question gets
  asked. The earlier "delete when done" decision was wrong for a different reason than tidiness: a
  guide that is gone cannot tell you what is still unconfigured, and "complete enough" is a property of
  the must-setup tier, not a reason to delete the guide. The cost is one profile home and one routing
  slot, paid knowingly.*
- **macOS:** what is the minimum honest gate? `uname` check and a README sentence is probably enough
  until the Linux path has been run by someone who is not its author.
- **What does the interview do on a machine that already has a harness?** Refuse by default; re-run in
  "add a profile" mode only with an explicit flag. Silent merging is how two writers end up on one
  profile.
