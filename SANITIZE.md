# SANITIZE.md — what was stripped, and why

This skeleton was extracted from a working personal setup. This file is the audit
trail: **everything removed, and the reason.** Read it before publishing, and
re-run the checks below if you add anything.

## Removed entirely (never copied)

| Item | Why |
|---|---|
| `memories/MEMORY.md`, `memories/USER.md` (all profiles) | Personal: who the user is, their projects, their preferences |
| `sessions/`, `state.db`, `*.jsonl` transcripts | Conversation history |
| `workspace/` (all profiles) | Registry contents, research memos, experiment artifacts |
| `.env` files (all profiles) | Credentials. Replaced by `.env.template` |
| `cron/` job definitions | Referenced personal destinations (a specific Discord channel) |
| `pets/` (custom pet + `pet-bridge` plugin + desktop overlay) | Personal side project |
| `auth.json`, `pairing/`, `platforms/` | Credentials and account linkage |

This matches Hermes' own distribution exclusions:

```
DEFAULT_DIST_OWNED  = SOUL.md, config.yaml, mcp.json, skills, cron, distribution.yaml
USER_OWNED_EXCLUDE  = memories, sessions, plans, workspace, home, backups, cache, local
                    + any credential store, at any depth
```

## Sanitized (kept, but generalized)

| File | Change |
|---|---|
| `profiles/playground-manager/SOUL.md` | The cost-incident post-mortem referenced a specific pet project and date. Replaced with an anonymized description — **the four hard-stop rules are verbatim and unchanged**, since they are the actual value. |
| `profiles/research-engineer/SOUL.md` | "the user's ecosystem" → "a Hermes multi-agent ecosystem"; the named orchestrator and a personal-project reference generalized; everything else (the sweep/verification method, the required tables) unchanged. The 19-vs-27 tool-count incident is already anonymous — kept as-is, because it is a real lesson. |
| `skills/hermes-ecosystem-ops/SKILL.md` | **Rewritten.** The source was ~35 personal-reference lines out of 149: this machine's paths, the user's board format, the pet workstream, the specific registry location. The generalized version keeps every transferable lesson (delegation guardrails, the reload gaps, memory hygiene, the profiles-vs-skills rubric, the checker design rules) and drops the specifics. |

## Unchanged (already generic)

- `profiles/default/SOUL.md` — the base agent prompt.
- `profiles/project-manager/SOUL.md` — board/registry presentation standards.
- `profiles/reporting-agent/SOUL.md`
- `profiles/health-check-doctor/SOUL.md`

Verified by grepping each for personal markers (`the user`, the assistant's name,
the user's project names, `/home/<user>`) before copying.

## Replaced with templates (values are machine-specific)

- `map/ecosystem-map.template.md` — the source map documented *one machine's*
  wiring (hostname, ports, container names, profile models). The template keeps
  the structure and the method; you fill in your own values.
- `map/ecosystem-map.checks.yaml` — the source checks asserted that machine's
  values. The template ships a few worked examples plus guidance.
- `map/scripts/map_check.py` — **paths parameterized** to `$HERMES_HOME` instead
  of a hardcoded home directory.

## Re-verify after any change

```bash
# No personal paths, no names, no secrets anywhere in the repo.
# Substitute YOUR OWN private markers — assistant name, project names, hostname:
grep -rniE "/home/[a-z]+/|YOUR_ASSISTANT_NAME|YOUR_PROJECT_NAME|YOUR_HOSTNAME" . \
  --exclude-dir=.git || echo "clean"

# No credential values (key NAMES are fine):
grep -rnE "^[A-Z_]+=.+" . --exclude-dir=.git --include=".env*" || echo "clean"
```

Both should report clean. If you add a file, add it to this list.
