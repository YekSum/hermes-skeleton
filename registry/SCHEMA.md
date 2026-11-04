# Registry schema

This is the *shape* of the registry, not its contents. Copy `board.md` and `projects.md` from this
folder, then fill them with your own items. Nothing here is about one installation.

## Two files, one writer

| file | holds | written by |
|---|---|---|
| `board.md` (+ `board.html`) | one row per work item, grouped by status | **exactly one profile** — the steward |
| `projects.md` | project inventory + a dated decisions log | the same steward |

Single writer is the load-bearing rule. The moment two profiles may write, one agent's mistake becomes
the next agent's fact — and nothing in the file says which one is wrong.

## Board format

Two top sections — **Real Projects** (work that ships) and **Hermes Agent Setup** (work on the
harness). Each repeats the same status subsections, always in this order:

`PLANNED · IN_PROGRESS · BLOCKED · NEEDS_REVIEW · READY_TO_PROMOTE · DONE`

Every item is a table row, never loose prose:

```
| ID | Task | Owner | Status | Priority | Created | Last Updated | Notes/Blocker |
```

Rules that keep it readable:

- **Stable IDs.** `RP-###` for real projects, `HA-###` for harness work. An ID never changes, so a
  row can be referenced from a chat, a note, or another profile's report without ambiguity.
- **Created is preserved forever.** A status move updates `Last Updated` only. Silent history
  rewrites are how a board stops being trustworthy.
- **Deferred is marked, not hidden.** `deferred: <reason>` with the condition that would revive it.
  A row parked in a live status with no owner is a lie about what is happening.
- **Blockers say what unblocks them.** "Blocked" alone is not a status, it is a shrug.
- **Priority as a fire count** — 🔥 low, 🔥🔥 medium, 🔥🔥🔥 high — or replace the convention wholesale
  and keep it consistent.
- **`board.html` is regenerated with `board.md`**, as real `<table>` markup, so previewing it shows
  tables rather than raw pipes.

## Projects file

One row per project: `name | status | repo/path | owner | one-line purpose`. Then a **Decisions log**:
`- YYYY-MM-DD: <decision> — <why, and what was rejected>`. The "what was rejected" half is what makes
the log worth keeping; a list of decisions without reasons cannot be re-litigated or learned from.

## The inbox

`inbox/` is how a profile that does **not** own the registry proposes a change to it. Contract in
`inbox/README.md`. Notes are consumed, never accumulated — an unconsumed inbox is a second source of
truth, which is the failure the single-writer rule exists to prevent.

## What does not belong here

Secrets, transcripts, copies of code, reports of finished work. A merged ticket already has its pull
request; a copy in the registry only drifts.
