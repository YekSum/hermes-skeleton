"""session-brief — inject a generated orientation brief on the first turn.

Why a hook and not a file: the brief must be rendered from the canonical stores
each session. A hand-written file would drift, which is the exact failure this
replaces. The script is deterministic and stdlib-only.

Contract (hermes_cli/plugins.py: pre_llm_call may return {"context": ...}):
  - fires on every model call, so we gate on is_first_turn
  - skipped for delegated subagents (parent_session_id set): the parent is briefed
  - fail-open: any error returns None and the turn proceeds unbriefed
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

_HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
SCRIPT = os.path.join(_HOME, "scripts", "brief.py")
LOG = os.path.join(_HOME, "cache", "session-brief.log")


def _profile_for_this_install() -> str:
    """Derive the profile from where this plugin lives.

    <home>/plugins/session-brief              -> default
    <home>/profiles/<name>/plugins/session-brief -> <name>
    """
    here = os.path.abspath(__file__)
    m = re.search(r"/profiles/([^/]+)/plugins/", here)
    return m.group(1) if m else "default"


def _render(profile: str) -> str:
    try:
        proc = subprocess.run(
            [sys.executable, SCRIPT, profile],
            capture_output=True, text=True, timeout=6,
        )
    except Exception:
        return ""
    return (proc.stdout or "").strip()


def register(ctx):
    def pre_llm_call(is_first_turn=False, parent_session_id="", session_id="", **_):
        try:
            if not is_first_turn or parent_session_id:
                return None
            # Arm control for measurement runs. File-based, not env-based: CLI
            # sessions may be served by the already-running gateway process, which
            # never sees an env var set in the caller's shell (verified — the env
            # guard silently failed and the brief was still injected).
            if os.environ.get("HERMES_BRIEF_DISABLE", "").strip().lower() in ("1", "true", "yes"):
                return None
            if os.path.exists(os.path.expanduser("~/.hermes/cache/brief.off")):
                return None
            profile = _profile_for_this_install()
            body = _render(profile)
            if not body:
                return None
            try:  # tripwire: proves the hook fired, one append per session
                with open(LOG, "a", encoding="utf-8") as fh:
                    fh.write(f"{session_id}\t{profile}\t{len(body)}\n")
            except Exception:
                pass
            return {
                "context": (
                    "<session-brief rendered=\"start of this session\">\n"
                    "This is current state rendered from the canonical files just now, "
                    "not recollection and not a summary someone wrote by hand. Answer "
                    "orientation questions from it directly; open the source file only "
                    "when you are about to EDIT it, or when you need detail this digest "
                    "omits.\n"
                    f"{body}\n</session-brief>"
                )
            }
        except Exception:
            return None

    ctx.register_hook("pre_llm_call", pre_llm_call)
