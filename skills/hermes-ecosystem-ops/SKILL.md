---
name: hermes-ecosystem-ops
description: "Use for ecosystem ops: board, delegation, harness changes."
version: 1.0.0
author: (your name)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, ecosystem, registry, kanban, delegation, budget, context, ecosystem-map, research, plugins]
---

# Hermes Ecosystem Operations

## When to Use

- Updating the canonical registry or Kanban board (status changes, new items, decisions-log entries)
- Delegating work to specialist profiles
- Delegating RESEARCH — the sweep/verification method and the deliverable tables
- Verifying or reporting spend from delegated experiments
- Verifying a delegated child's self-reported numbers against the transcript
- Deciding where a piece of context belongs (profile vs working dir vs registry vs knowledge store)
- Recording or auditing the ecosystem/harness structure
- Extending the harness: writing a plugin or hook
- Evaluating a third-party plugin/provider/skill ("is it worth it?", "does it save tokens?", "is it safe?")

Standing procedures for a multi-profile Hermes setup: one orchestrator profile plus specialist profiles.

## Canonical registry and board

- Keep the registry in **one** profile's workspace (e.g. `profiles/<project-manager>/workspace/registry/`): `projects.md` (registry + Decisions log), `board.md`, `board.html`.
- **ONLY that profile writes them.** Everyone else reads. This single-writer rule is what stops two agents corrupting shared state.
- To update, delegate to the owning profile with exact row/section edits and a one-line confirmation request. **Verify with a grep/read afterwards** — reports are usually trustworthy but writes must be confirmed.
- Board conventions that keep it usable: fixed sections; every item a table row (`ID | Task | Owner | Status | Priority | Created | Last Updated | Notes`); stable IDs that persist across edits; blockers state what blocks *and* what unblocks; deferred items say `deferred: <reason>`; **Created is set once and preserved on status moves**; regenerate the HTML companion on every change.
- Mark experimental work with a prefix (e.g. `[experiment]`) rather than giving it its own section — an experiment can also belong to a project, so a separate section fragments items.
- When rendering a board for a terminal, use a unicode box table; raw markdown pipe-tables render as vertical text in a CLI and inside chat clients that don't render tables. For chat clients that DO render code blocks monospace, a unicode table inside a fenced code block aligns correctly.

## Delegation guardrails (every delegate_task)

- **ALWAYS set the task's `profile` field.** Omit it and the child inherits the parent's model instead of the profile's configured one.
- **Child skill registries are built at process start.** A skill installed mid-session is on disk and appears in `hermes -p <profile> skills list`, but a delegated child's `skill_view('<name>')` returns `Skill '<name>' not found` because the running process never reloaded. Fixes: restart the process, or point the child at the skill's `scripts/` path so it runs the tool directly via terminal. Cost of missing this: a research task silently loses a whole source leg and falls back to a weaker method.
- **Same class of gap for plugins:** `hermes plugins enable <name>` reloads hooks in the running gateway, but an already-started session never picks them up. Verify in a FRESH session (`hermes chat -q "..."`).
- **Put stop-conditions IN the delegation prompt as failure semantics:** "On any provider/model error: stop and report; do NOT substitute a model. If the named model is blocked, the task FAILS — return that as the result." Prose guardrails like "no switching without informing" get read as a *reporting duty*: children have completed the task via a silent fallback chain and then 'informed' in the wrap-up.
- **Name exactly one model per modality** in the goal. State the model id, never "or equivalent".
- **NEVER relay a child's self-reported spend as verified.** A missing/zero `usage.cost` means spend is UNKNOWN, not zero. Reconcile against the provider's billing surface before quoting any figure.
- **Default budget cap for unattended delegated experiments:** a small explicit number. Anything larger needs the user's explicit figure in the task text.
- **Unattended children lie in two specific ways:** claiming artifacts were saved when they were not (search for the file before relaying a save claim), and silent model/provider fallback. Both are verified, not assumed.
- **Self-reported numbers in a deliverable are suspect.** A child's own summary table (e.g. "tool usage: 19 terminal calls") can be wrong — count from the transcript. If a table disagrees with reality, the table is worse than no table.

## Delegation verification pattern

1. Dispatch with the `profile` field + stop-conditions + named models + budget.
2. On completion, verify externally: files exist (find/ls), spend reconciled, no unexpected model names in the live transcript (`$HERMES_HOME/cache/delegation/live/<delegation_id>/task-*.log`).
3. Only then relay results upward as verified.

## Delegating research

- Ask for a **multi-source sweep** (primary docs, papers, community/forum discussion, blogs/changelogs, code/issues) — not one `web_search`.
- Require a **verification loop**: a forum thread is evidence that people *report* something, not that it is true. Every material claim from a discussion gets a second independent search and a `corroborated` / `contradicted` / `unsupported` label. Unsupported claims are sentiment only.
- Require **full URLs** for every source (a memo citing file paths with no URLs is a weakness), and a **coverage-gap report** per source type.
- Require the two tables: **tool usage** (counted, not recalled) and **provenance** (`[CODE]` / `[DOCS]` / `[INFER]`).
- Forum tooling may be rate-limited (anonymous Reddit is ~1 request/minute); budget calls accordingly or register an app for a higher limit.

## Memory hygiene (MEMORY.md / USER.md)

- Built-in memory is **unconditional**: whatever sits in MEMORY.md/USER.md is injected into every session's prompt, every turn, whether relevant or not. Budgets are small and running near-full is normal. Place facts deliberately:
  - **Universal** (changes how ANY session behaves) → memory.
  - **Task-specific** → a skill (loads on demand; only its one-line description costs prompt space).
  - **Harness/structure facts** → the ecosystem map.
  - If a fact already lives in a skill or the map, memory keeps at most a **pointer** — never a copy.
- **Archive before editing memory**: copy `memories/MEMORY.md` and `memories/USER.md` into `memories/archive/<NAME>-<timestamp>.md` first.
- **Relocate, never delete.** A pruned entry moves into a skill or becomes a pointer; nothing is destroyed. Outright deletion is a user decision only. (Precedent: the skill Curator archives stale skills and never deletes.)
- **Only a live session writes memory.** Delegated children run with `skip_memory=True`, so memory accrues to the profile whose session is live. Specialist profiles therefore hold no memory files until they run standalone.
- A periodic health check should **diagnose** memory (usage vs limit, band, duplicate and misfiled entries) and **propose** relocations with the criterion cited — read-only, never editing.

## Profiles vs skills — when a specialist earns its own profile

- A **skill** is a document loaded into the CURRENT agent's context, executed by that agent with its model, credentials and sandbox. A **profile** is a separate Hermes home that differs on five axes a skill structurally cannot provide: **model**, **context** (fresh, isolated), **credentials** (own `.env`), **isolation** (own terminal backend/sandbox), **lifecycle + audit** (can run standalone, keeps its own session store).
- **Rubric:** a profile earns its existence if it differs on model, credentials, isolation, or lifecycle — or needs a constraint enforced by **structure** rather than convention. Otherwise it is a skill wearing a costume, at the cost of one more home to keep in sync.
- Corollary: memory only pays off for an agent that **recurs with continuity**. A stateless per-task worker gains nothing from private memory — its durable knowledge belongs in SOUL (behaviour), skills (procedure) and artifacts (output).

## Deterministic verification of the ecosystem map

- The map describes the harness; keep it **mechanically checkable**. Pair each checkable claim with the shell command that proves it, in a checks file, and run it with a small script.
- Design rules that make it usable unattended:
  - **Fail loud, silent when healthy.** Healthy prints nothing; every internal failure (missing/unparseable checks file, zero checks, no usable interpreter) prints an error on **stdout**. Otherwise a broken checker is indistinguishable from a healthy system.
  - **Pin the profile.** `hermes` resolves its profile from `$HERMES_HOME`; an unscoped `hermes config get` reads whichever profile the shell is in and produces **phantom drift** when run from another profile's context. Pass `-p <profile>` explicitly and pin the env.
  - **A DRIFT can mean the check is wrong, not the system.** Three times in one build the *check* was the bug (a truncated CLI table, a YAML-escaped regex that matched nothing, a nested-quote shell error). Always ask which side is wrong.
  - **It is a regression test, not an auditor.** It only tests claims that were encoded, so it cannot discover omissions. Green means "nothing we thought to check has changed" — never "the map is true".
- Wire it as a cron `script:` (stdout injected into the prompt) to remove mechanical archaeology from the model's job, keeping the model for interpretation. A cron `monitor:` gate can skip the model entirely when output is unchanged — but only after profile-pinning and fail-loud are in place, and it makes healthy runs silent.
- Keep the map's advertised check count in sync with the checks file via a self-consistency check.

## Extending the harness

- **Plugins** register hooks from `register(ctx)`; hook callbacks receive keyword args and should accept `**kwargs`. Observer hooks are fail-open — never let a plugin raise into the agent loop. Verify hook names against `hermes_cli.plugins.VALID_HOOKS`.
- Prefer observation-only plugins. Anything that changes behaviour belongs behind an explicit approval.
