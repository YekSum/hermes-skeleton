---
name: onboarding-guide
description: "Use when running the first-run interview or answering setup questions."
version: 1.0.0
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [onboarding, setup, first-run, tutorial]
---

# Running the first-run interview

The SOUL carries the behaviour (tiers, tone, what never to do). This file carries the **exact wording,
the probes, and where each answer is written** — so the interview can be rewritten without touching a
profile home.

## Before you speak

Run these first, so the first message is informed rather than generic. None of them cost a model call.

```bash
H="${HERMES_HOME:-$HOME/.hermes}"

# which machine? (decides whether the rest is valid at all)
uname -s
grep -qi microsoft /proc/version && echo "platform: wsl" || echo "platform: native-linux-or-mac"
echo "distro: ${WSL_DISTRO_NAME:-n/a}"

# what already exists?
ls -d "$H"/profiles/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null
[ -f "$H/ecosystem-map.md" ] && echo "map: present" || echo "map: missing"
[ -f "$H/ecosystem-map.checks.yaml" ] && echo "checks: present" || echo "checks: missing"

# verified?
python3 "$H/scripts/map_check.py" 2>/dev/null; echo "checker exit=$?"

# credentials, by NAME only — never print a value
grep -oE '^[A-Z_]+=' "$H/.env" 2>/dev/null | tr -d '='

# model configured?
hermes -p <profile> config get model 2>/dev/null | head -1
```

Then greet according to what you found: fresh machine → the full introduction; already green → "you're
set up, what do you need?" and stop there.


## When the platform is not supported

Say it in one short message, then stop — do not offer a partial path:

> This runs on Ubuntu, or on Windows through WSL. macOS isn't supported yet — the setup scripts assume
> Linux tools, and half-working instructions would waste your afternoon more than this message does.
> If you want to try it anyway, the honest starting point is a Linux VM or WSL.

Then record nothing except the platform line, and end the session. A refusal that also half-installs is
the worst of both.

## The opening

Seed turn is `hi` and nothing else. Your first message:

> Hi — I'm your assistant. I'll get this harness working, then answer questions about it any time.
> First: what should I call myself?

Then, before asking anything technical, one short paragraph on the shape — **and name delegation**,
because it is the part nobody expects:

> Quick sketch while you think: there are several *profiles* here — separate agents with their own
> model, credentials and sandbox. One of them is me. Your everyday work goes to whichever one is best at
> it, and each handoff leaves a transcript you can read. That's the difference between one assistant and
> a small team you can audit.

## The question bank

Ask in order. Skip anything already answered by a probe. One at a time, short.

| # | ask | writes to | default if skipped |
|---|---|---|---|
| 1 | "What should I call myself?" | default profile `SOUL.md` line 1 + `USER.md` | "your assistant" |
| 2 | "What do you actually want to work on?" — free text, no options | `USER.md` (intent) + one board row | no board row |
| 3 | "Which of these do you need?" — project tracking / research / building / health checks, one plain line each | creates only the chosen profiles (deleting the others is a `bootstrap.sh` concern; say what you did) | the core four |
| 4 | "Which provider and model?" — then hand them the terminal command for the key | `config.yaml` model; key via the **script**, never the chat | the provider already in `.env` |
| 5 | "Where do you want to talk to me — just here, or a messaging app?" | optionally: gateway config; **never** a token in chat | terminal only |
| 6 | "Anything you want me to never do?" | `USER.md` (hard limits) | none |

Optional follow-ups, only if they engage: a specific first project; scheduling the weekly drift check.

**Rule for every answer:** write it, then confirm in one clause ("noted — that's going in your
preferences"). An unwritten answer is a question you will ask again next session.

## Where things go

| kind of fact | home | never |
|---|---|---|
| how to behave, preferences, hard limits | `USER.md` | the map |
| facts about this machine (ports, services, providers) | `ecosystem-map.md` | `USER.md` |
| work to do | the board | chat |
| procedures | skills | memory |

One memory line total for the whole interview, and only if it changes behaviour every session.

## The finish

```bash
python3 "$H/scripts/map_check.py" --verbose
```

Say the result out loud with numbers (`67/67, 0 drift`), not "all good". If something fails: fix it, or
record it in the map as deliberately deferred **with the reason**, then continue.

Then the closing text, once:

> That's the harness running. **You can stop here** — everything works.
> Optional, whenever you want: talk to me from a messaging app, add the desktop app, or schedule a
> weekly drift check so problems surface without you looking.
> Try this first: ask me to put something real on the board.

## Answering later questions

1. Re-derive the state (the probes above). Do not assume your last run's state.
2. Answer the question asked, in the smallest number of steps.
3. Only if it is relevant, offer **one** optional next step.
4. Never restart the interview. A returning user gets an answer, not a checklist.
