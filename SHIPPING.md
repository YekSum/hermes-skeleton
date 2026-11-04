# What ships, and what never does

This repo is a **rebuild kit**, not a backup. The test for every file is not "is it safe to
publish?" — it is:

> **Would someone starting fresh need this to build the same *shape*?**
> And: **does it encode a decision they have not made yet?**

A file that passes the first test and fails the second is a preference, not a structure. Preferences
stay home, even when they are perfectly safe to publish.

That is why the profiles here ship **empty of territory**. Rules travel — "one writer per store",
"facts point to the source, never copies". Memberships do not — your project names, your board
sections, your machine's ports. The skeleton should be blank until its user fills it in, and should
then drift toward *their* habits rather than pretending to be ours.

## The four classes

| class | meaning | drift policy |
|---|---|---|
| **structure** | Needed to rebuild the mechanism. No personal content possible. | copy verbatim; a diff from the source is an **error** |
| **template** | Structure plus placeholders. Machine- or person-specific values blanked. | regenerated; a diff is an **error** unless it is a placeholder |
| **curated** | Written for a public reader. Deliberately differs from the private original. | never overwritten; divergence is **info**, ported by hand |
| **never** | State, secrets, or content that only describes one installation. | blocked by `.gitignore` and a pre-commit hook |

## The manifest

**structure — ship as-is**

- `bootstrap.sh` — creates profiles, wires delegation, installs the skill
- `scripts/brief.py` — renders the session brief from the canonical stores
- `plugins/session-brief/` — the first-turn injection hook
- `map/scripts/map_check.py` — the deterministic checker
- `profiles/<name>/distribution.yaml` — per-profile install manifest

**template — ship with placeholders**

- `profiles/<name>/SOUL.md` — behavioural rules, **no territory**; each ends with a
  `## Personalize — required before use` block that must be deleted after filling in
- `map/ecosystem-map.template.md` — the harness map, blanked
- `map/ecosystem-map.checks.yaml` — the claim/command pairs, with *your* claims removed
- `registry/SCHEMA.md` + empty `board.md` / `projects.md` — the board format without the board
- `registry/inbox/README.md` — the proposal contract
- `.env.template` — key **names**, never values

**curated — hand-written, never exported**

- `README.md` — what this is, how to take it to another machine
- `SHIPPING.md` — this file
- `SANITIZE.md` — the pre-publish checklist
- `skills/hermes-ecosystem-ops/SKILL.md` — the operating manual. Deliberately *not* the live copy:
  the live one names the assistant, the dashboard, a pet, absolute paths and a password incident. A
  verbatim export would republish all of it in one commit, with no error raised.
- ~~`experiments/brief-ab/`~~ — **moved out of this repo.** The numbers are the argument for the
  mechanism, but the experiment measures *one* installation's board, paths and questions against
  *its* facts. Publishing it invites a reader to assume the numbers transfer to theirs. It lives in
  the private repo; this one keeps the mechanism and the method, not the measurement.

**never**

`.env` values · `*.db`, `*.db-wal`, `*.db-shm` · `auth.json` · `memories/` · `sessions/` ·
`state/` · `cache/` · `logs/` · `cron/` · `desktop/` (session token) · `bot_relay/` · `pairing/` ·
`.skills_prompt_snapshot.json` · backups · **the filled `ecosystem-map.md`** · **the filled
`board.md` / `projects.md`**

The last two are the honest exclusions. The filled map is the single most useful document in a live
harness and the least useful in a repo, because it is a statement about one machine. On a new machine
its value comes from running the checks and writing what *they* report.

## The publication bar (this repo is public)

Beyond secrets, anything that identifies the installation must go. The check:

```bash
grep -rniEf .sanitize-patterns --exclude=.sanitize-patterns --exclude-dir=.git .
```

Add a line to `.sanitize-patterns` whenever a new identifier appears — the pattern list lives in one
file so the doc, the checker and `export.sh` cannot disagree.

Must return nothing. Current state: clean.

What that bar cost, concretely, in the profile SOULs: an assistant name in a role table, a
spend-cap instruction addressed to one profile by name, a container-hostname workaround for one
search backend, and an incident narrative naming one experiment. Each was replaced with the rule
that survived it — "agree a spend cap with the orchestrator", "verify the host bridge address" — and
the narrative was dropped. The lesson travelled; the biography did not.

## Keeping it honest

The repo is not a snapshot to be re-copied when someone remembers. `export.sh` owns it, driven by
`export.manifest` (one line per file: `class`, repo path, live path).

- `./export.sh --check` — diffs `copy` files byte-for-byte and compares `manual` files against the
  **source hash** recorded in `.export-lock`. Exits 1 on any copy drift or re-port need, so it can be
  a pre-commit gate. `own` files are never compared.
- `./export.sh --write` — refreshes `copy` files only. It stages them, runs the publication bar over
  the staged content, and **refuses to write if anything trips** — so a leak is blocked before it
  lands, not discovered later. `manual` files are never touched: regenerating prose from prose is how
  a careful redaction becomes an accident.
- `./export.sh --accept` — after you re-port a `manual` file by hand, records the new source hash.
  The lock stores **repo-relative paths only**, so it carries no machine paths.
- `./export.sh --list` — the manifest with every file's current status.

`hooks/pre-commit` runs all three gates on every commit: installation identifiers anywhere in the
tree, secret-shaped strings in the staged diff, and `export.sh --check`. Install it with:

```bash
cp hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

A stale copy is therefore a build failure, not a thing someone notices three weeks later — and a
secret is a refused write rather than a `git rm` after the fact.
