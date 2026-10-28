# Ecosystem Map — <YOUR SETUP NAME>

> The "README for Hermes": how this multi-agent ecosystem is wired, who owns what, and how to move it.
> **Writer:** <which profile owns this file — normally the orchestrator>.
> **Auditor:** <a read-only profile that verifies it, if you have one>.
> **Rule:** a harness change is not done until this file reflects it.
> **Mechanically verified:** `ecosystem-map.checks.yaml` + `scripts/map_check.py` (<N> no-LLM checks).
> Last written: <YYYY-MM-DD> by <who>.

<!--
HOW TO USE THIS TEMPLATE

This is the "exoskeleton": the structure that made a working setup legible.
Fill it in for YOUR machine. Delete sections you don't need — an accurate short
map beats a comprehensive stale one.

The value is not the prose; it is that every claim here can be checked. For each
statement you make, ask: "what command would prove this?" If there is one, add it
to `ecosystem-map.checks.yaml`. If there isn't, it's a judgement call — mark it as
one, and don't let a green checker imply it was verified.

Sections marked [OPTIONAL] are worth keeping only if you actually have that part.
-->

---

## 0. How to use this file

| If you need to know… | Read |
|---|---|
| who to ask for a given thing | §1 Routing |
| how work gets delegated | §2 Delegation topology |
| what's actually installed/wired | §3 Harness inventory |
| how to move this to another machine | §4 Migration manifest |
| how the pieces connect | §5 Topology |
| what's uncertain or unverified | §6 Open questions / drift log |

Single writer = <profile>. Everyone reads. No other profile edits this file.
<If you have an auditor profile:> <profile> independently verifies it and reports mismatches (§6).

---

## 1. Routing — who to ask for what

| Profile | Role | **Owns (single writer of)** | **Can answer** | Model | Provider | Terminal |
|---|---|---|---|---|---|---|
| **default** | Orchestrator / front door | <this map; harness changes> | routing, general work | <model> | <provider> | <local/docker> |
| **<specialist>** | <role> | <what it alone writes> | <question types it is the authority for> | <model> | <provider> | <backend> |

**Routing rule:** a recall question ("do you remember X?") is a *retrieval* request — delegate to the owner above and answer from the returned record. Keep the orchestrator's own memory thin: identity plus this routing table, not project detail.

---

## 2. Delegation topology

- **Backend:** `delegation.backend = <profile_routes | model_map | ...>`
- **Orchestrator:** <which profile fans out>. Only one should, or routing becomes ambiguous.
- **Routes:** <list the specialist profiles>
- **Pin rule:** every `delegate_task` MUST set the task's `profile` field, or the child inherits the parent's model instead of the profile's configured model.

```
        <orchestrator>
              │  delegate_task(profile=…)
   ┌──────────┼──────────┬──────────┐
   ▼          ▼          ▼          ▼
<spec A>   <spec B>   <spec C>   <spec D>
```

---

## 3. Harness inventory

### Services (systemd user units) [OPTIONAL]
| Unit | Purpose | Port | State |
|---|---|---|---|
| `hermes-gateway.service` | messaging gateway | — | enabled / active |
| `hermes-serve.service` | desktop app backend | <port> | enabled / active |

<!-- Distinguish ENABLED from ACTIVE. An enabled-but-crashed unit passes an
     is-enabled check — check both. -->

### Providers & credentials
| Provider | Used by | Key (in `.env`) |
|---|---|---|
| <provider> | <profiles> | `<KEY_NAME>` |

Secrets live in each profile's `.env` — never in `config.yaml`.

### Web tools [OPTIONAL]
| Setting | Value | Role |
|---|---|---|
| `web.backend` | <value> | primary general backend |
| `web.search_backend` | <value> | search |
| `web.extract_backend` | <value> | page extraction |

<!-- Do not conflate these: they are separate backends and a map that says
     "search = X, fallback Y" is usually wrong about which is primary. -->

### Plugins
| Profile | Plugins (enabled) |
|---|---|
| <profile> | <plugin names> |

### Terminal isolation
| Backend | Profiles |
|---|---|
| `local` | <profiles> |
| `docker` | <profiles> |

<!-- Note: a docker-sandboxed profile cannot read its own profile .env, and
     `hermes` CLI calls inside it may resolve a different home. -->

### Other subsystems [OPTIONAL]
<Anything else wired: pets, computer-use backend, dashboard auth, cron, MCP
servers, connectors, connectors registry state. If it exists, it belongs here —
an undocumented subsystem is what an audit is for.>

### Default-home state files [OPTIONAL]
| Path | What it holds |
|---|---|
| `<db>` | <what> |
| `memories/archive/` | timestamped MEMORY/USER snapshots taken before each memory edit |
| `cache/delegation/live/<id>/` | per-delegation transcripts — the audit trail for anything a specialist did |

### Connections
- **<platform>** — <state>, which profiles it serves, which channel(s) are allowed.
- **Desktop** — <how the app connects>.

### Skills
- <Which profiles carry which skills. Skills are per-profile and auto-accumulate —
  which is why work vs personal context should be split by profile family.>

---

## 4. Migration manifest (move to another machine)

Copy:
1. `<HERMES_HOME>/` — the default home, including this file and its checks.
2. `<HERMES_HOME>/profiles/*` — every profile home.

Re-create / re-enable (not carried by a file copy alone):
- systemd user services (enable + start + linger).
- Any containers or self-hosted services.
- Scheduled jobs — and their attached scripts.
- Verify the delegation routes survived the copy: `config set` replaces the whole list.
- Re-check each profile's model still resolves (model ids get deprecated).
- Re-check dashboard auth and any platform pairing.

<!-- This section is the reason the map earns its keep. Update it whenever you
     wire something new, while you still remember how. -->

---

## 5. Topology

```
   <platform>  ───▶ <gateway service>  ───▶ <profiles>
   <desktop>   ───▶ <serve service>    ───▶ <orchestrator>
   web tools   ───▶ <search backend>
   sandboxes   ───▶ <containers>
   LLMs        ───▶ <providers>
   Files       ───▶ <HERMES_HOME> + profiles/<name>/
```

---

## 6. Open questions / drift log

| Date | Item | Status |
|---|---|---|
| <YYYY-MM-DD> | <what was found, by whom> | **fixed** / open / deferred |

<!-- Log every drift an audit finds, and every deliberate deferral. This is what
     stops the same discovery being made twice. -->
