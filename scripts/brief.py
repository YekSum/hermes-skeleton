#!/usr/bin/env python3
"""Session brief — a short, generated orientation block for one Hermes profile.

Reads the canonical stores and prints what a profile needs to know at the
start of a session, so it does not have to open 30 KB files to get oriented.

Deterministic: stdlib only, no model call, no network, no writes.

Usage:  python3 brief.py [profile]        # profile defaults to $HERMES_PROFILE or "default"
Exit:   always 0. On any error it prints nothing, so a caller (hook, shell
        prompt) never breaks a turn over a missing file.
"""
from __future__ import annotations

import datetime
import os
import re
import sys

HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
REGISTRY_PROFILE = os.environ.get("BRIEF_REGISTRY_PROFILE", "project-manager")
REG_DIR = os.path.join(HOME, "profiles", REGISTRY_PROFILE, "workspace", "registry")
BOARD = os.path.join(REG_DIR, "board.md")
MAP = os.path.join(HOME, "ecosystem-map.md")

ROLE_OWN = {
    "default": "the ecosystem map (harness facts), routing, and memory discipline",
    "project-manager": "projects.md + board.md + board.html — the registry, sole writer",
    "research-engineer": "research memos under your workspace; findings, not project code",
    "playground-manager": "experiments in your own sandbox; never a shared or production tree",
    "reporting-agent": "read-only status consolidation from the registry and board",
    "health-check-doctor": "read-only diagnosis of the harness; you report drift, you never fix it",
    "coder": "application code in project repos via the Claude Code CLI",
}

ROLE_RULES = {
    "default": [
        "Route, do not warehouse: a recall question goes to the owning profile, answered from its record by ID.",
        "Memory holds identity + pointers; facts live in the map, project state in the registry.",
        "A harness change is not done until ecosystem-map.md AND its checks reflect it.",
    ],
    "project-manager": [
        "Record, do not route. You are the sole writer of projects.md / board.md / board.html.",
        "Stable IDs (RP-/HA-), Created date preserved on status moves, board.html regenerated on every change.",
        "Deferred items marked `deferred: reason`, never left sitting in a live status.",
        "Merge the inbox on each run (registry/inbox/) — see 'Inbox' below.",
    ],
    "research-engineer": [
        "Multi-source sweep: primary sources, papers, community, code. One web_search is not research.",
        "Label forum-derived claims corroborated / contradicted / unsupported.",
        "Write findings to your workspace memos; propose registry changes via the inbox, never by editing the board.",
    ],
    "playground-manager": [
        "Bounded experiments in your own sandbox. Record hypothesis, cost and artifacts.",
        "You cannot promote anything without explicit user approval.",
    ],
    "reporting-agent": [
        "Read-only: consolidate, cite by ID, escalate. Execute nothing.",
        "Report what the registry says, not what you recall from chat.",
    ],
    "health-check-doctor": [
        "Read-only. Diagnose and report drift; never edit the map, registry, memory or skills.",
        "Run map_check.py before claiming the harness matches its documentation.",
    ],
    "coder": [
        "Build from a written brief: goal, repo path, acceptance criteria, constraints, authorization.",
        "Never commit, push or open a PR without explicit authorization in the brief.",
        "Never touch another profile's directories, memories, cron, or the registry.",
    ],
}


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def board_rows() -> list[dict]:
    rows = []
    for line in _read(BOARD).splitlines():
        s = line.strip()
        if not re.match(r"^\|\s*(RP|HA|HP)-\d+", s):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) >= 8:
            rows.append({"id": cells[0], "task": cells[1], "owner": cells[2],
                         "status": cells[3], "pri": cells[4], "note": cells[7]})
    return rows


def map_table(section: str) -> list[list[str]]:
    out, inside = [], False
    for ln in _read(MAP).splitlines():
        if ln.startswith("### "):
            inside = section.lower() in ln.lower()
            continue
        if inside and ln.startswith("|"):
            cells = [c.strip() for c in ln.strip("|").split("|")]
            if not re.match(r"^:?-{2,}", cells[0].replace(" ", "")):
                out.append(cells)
    header = {"unit", "provider", "setting"}
    return [r for r in out if r[0].lower() not in header]


def clip(text: str, n: int) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def inbox_pending() -> int:
    try:
        return len([f for f in os.listdir(os.path.join(REG_DIR, "inbox"))
                    if f.endswith(".md") and not f.startswith("README")])
    except OSError:
        return 0


def services_section(L: list[str]) -> None:
    rows = map_table("Services")
    if not rows:
        return
    L.append("## Services (systemd user units)")
    for r in rows:
        if len(r) >= 4:
            L.append(f"- {r[0]} — {clip(r[1], 54)} — port {r[2]} — {r[3]}")
    L.append("")


def web_section(L: list[str]) -> None:
    rows = map_table("Web tools")
    if not rows:
        return
    L.append("## Web backends (three, do not conflate)")
    for r in rows:
        if len(r) >= 3:
            L.append(f"- {r[0]} = {r[1]} ({clip(r[2], 40)})")
    L.append("")


def board_section(L: list[str], *, full: bool, mine: str | None = None) -> None:
    rows = board_rows()
    if not rows:
        return
    openc = [r for r in rows if r["status"] != "DONE"]
    if mine:
        openc = [r for r in openc if mine.lower() in r["owner"].lower()]
    done = len(rows) - len([r for r in rows if r["status"] != "DONE"])
    L.append(f"## Board: {len(rows)} items, {done} done, {len(openc)} open"
             + (f" (owned by {mine})" if mine else ""))
    order = ("IN_PROGRESS", "BLOCKED", "NEEDS_REVIEW", "READY_TO_PROMOTE", "PLANNED")
    for status in order:
        sel = [r for r in openc if r["status"] == status]
        if not sel:
            continue
        L.append(f"### {status} ({len(sel)})")
        shown = sel if full else sel[:6]
        for r in shown:
            line = f"- {r['id']} · {clip(r['task'], 58)} · {r['owner']}"
            if r["note"]:
                line += f" · {clip(r['note'], 60)}"
            L.append(line)
        if len(sel) > len(shown):
            L.append(f"- …+{len(sel) - len(shown)} more")
    L.append("")


def build(role: str) -> str:
    L = [f"# Brief — {role} — {datetime.date.today().isoformat()}", ""]
    L.append(f"You own: {ROLE_OWN.get(role, 'your own workspace')}.")
    p = inbox_pending()
    if p:
        L.append(f"Inbox: {p} note(s) waiting in registry/inbox/ — merge or discard each on this run.")
    L.append("")

    if role in ("default", "health-check-doctor"):
        services_section(L)
        web_section(L)
    if role in ("default", "health-check-doctor", "reporting-agent"):
        board_section(L, full=False)
    elif role == "project-manager":
        board_section(L, full=True)
    elif role in ("research-engineer", "coder", "playground-manager"):
        board_section(L, full=False, mine="research" if role == "research-engineer" else
                      ("coder" if role == "coder" else "playground"))

    rules = ROLE_RULES.get(role)
    if rules:
        L.append("## Rules that bind you")
        L.extend(f"- {r}" for r in rules)
        L.append("")

    L.append("## Pointers (read on demand, never copy)")
    L.append("- Harness facts: ~/.hermes/ecosystem-map.md (+ .checks.yaml, scripts/map_check.py)")
    L.append("- Work items: registry/board.md · decisions: registry/projects.md Decisions log")
    L.append("- Procedures: your skills · inbox contract: registry/inbox/README.md")
    return "\n".join(L)


def main() -> None:
    role = (sys.argv[1] if len(sys.argv) > 1 else
            os.environ.get("HERMES_PROFILE") or "default").strip() or "default"
    try:
        text = build(role)
    except Exception:  # never break a caller over a brief
        return
    if text.strip():
        sys.stdout.write(text.rstrip() + "\n")


if __name__ == "__main__":
    main()
