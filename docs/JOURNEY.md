# Onboarding journey — zero to green

**Status:** draft, not implemented. Board item HA-023. Gates HA-018 / HA-021 (pick one to build),
and feeds RP-008.
**Platform:** **Ubuntu / WSL first.** macOS is explicitly out of scope until the Linux path is boring;
the installer must *say so and stop*, not half-work.

---

## The one problem that decides the whole shape

**The interview cannot run before a model is configured.** The interviewer is an agent; an agent needs
a provider and a key. So the first stage can contain no conversation at all — it must be a plain
script, because at that moment there is nothing to talk to yet.

That is why stage 1 is a shell/python step and stage 2 is the chat. Everything else follows from it.

---

## Stage 0 — prerequisites (README, copy-paste only)

Two things must already be true, and the README says them in two lines:

1. Hermes Agent is installed and `hermes --version` works.
2. You are on Ubuntu or WSL. On anything else the next command refuses and explains.

No judgement calls, no profiling, nothing to read beyond the two lines.

## Stage 1 — `./setup.sh` — key, model, no LLM

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
- prints exactly one thing on success: `✓ model reachable — starting the interview`.

Design rules for this stage:

- **Never echo or log the key.** No `set -x`, no writing it into a log file, no "your key is sk-…xyz".
- **Verifiable, not assumed.** A wrong key must fail here, not 200 lines into the interview.
- **Idempotent.** Running it twice changes nothing and asks nothing already answered. `--check` mode
  reports state without writing.
- **No secrets in the repo, ever.** This script writes to `.env`; it never writes to a tracked file.

## Stage 2 — `./start-setup.sh` — the interview

One command opens a chat session with the onboarding prompt. This is the first moment the skeleton
introduces itself, and the order of the conversation matters more than the wording:

1. **Name first.** "I'm your assistant — what should I call myself?" Cheap, personal, and it makes the
   rest of the conversation feel like a relationship rather than a wizard.
2. **Introduce the skeleton in plain language**, before asking for anything. What a profile is, why
   there are several, what the board is for, how memory works (standing orders in `MEMORY.md`, facts
   in the map, a short brief generated at every session start). Two short paragraphs — no jargon dump.
   A user who does not understand the shape cannot answer questions about it.
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

## Stage 5 — optional: the desktop app

**Here, at the end, and optional.** Reasons:

- It is a **client**, not part of the harness. The ecosystem is fully working and verifiable without it.
- It adds failure surface — a serve service, a session token, and on WSL a Windows-side install. That
  is a bad thing to put in front of someone who has not yet seen anything work.
- It gives the journey a satisfying finish: *"now open the app and say hello"*.

The README entry is one line, marked optional, with the honest caveat that on WSL the app installs on
the Windows side.

**The case for moving it earlier** — offered to the interview as an alternative surface — is real but
weak: a GUI is nicer for a non-technical user *during* the interview, but it doubles the places a first
run can fail before the user has any evidence the thing works. If it does move, it belongs between
stage 1 and stage 2, never inside stage 1.

---

## Open questions

- **Where does the onboarding agent run?** In the default profile (which exists on a fresh install), or
  as a throwaway profile that deletes itself? The former is simpler; the latter keeps the user's first
  profile clean of setup chatter.
- **Does the interview create profiles via `bootstrap.sh`, or write them itself?** Reusing bootstrap
  keeps one implementation of profile creation; it also means the interview must handle bootstrap's
  refusals.
- **How is the interview shipped?** A prompt + a skill, a small CLI wrapper, or a profile-level
  distribution? (This is the HA-018 vs HA-021 decision — pick one, not both.)
- **macOS:** what is the minimum honest gate? `uname` check and a README sentence is probably enough
  until the Linux path has been run by someone who is not its author.
- **What does the interview do on a machine that already has a harness?** Refuse by default; re-run in
  "add a profile" mode only with an explicit flag. Silent merging is how two writers end up on one
  profile.
