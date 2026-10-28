#!/usr/bin/env python3
"""map_check.py — deterministic, no-LLM verification of ecosystem-map.md claims.

Each check in the checks file pairs a CLAIM (what the map asserts) with the shell
command that proves it. This script runs them and reports DRIFT (claim vs reality).

Why it exists: a health check that spends model tokens doing mechanical archaeology
is expensive and error-prone — a model can misread command output; a script cannot.
This does the mechanical part for free and deterministically, so a model is only
needed to interpret and prescribe.

Usage:
    python3 map_check.py             # drift lines only; prints NOTHING when healthy
                                     # (deterministic + empty == safe cron `monitor` gate)
    python3 map_check.py --verbose   # full PASS/DRIFT table for humans
    python3 map_check.py --exit-code # exit 1 when drift found (for CI/manual use)
    python3 map_check.py --summary   # always print a one-line summary (cron `script:`)
    python3 map_check.py --checks <path>

Design rules (each learned the hard way):
  * Never raises on a failing check — a check that errors is reported as drift
    with the error text, not a crash.
  * Output ordering is fixed (file order) and no timestamps are printed, so an
    unchanged system yields byte-identical output.
  * Exit code is 0 by default so a cron runner never treats drift as a job failure.
  * FAIL LOUD, SILENT WHEN HEALTHY: healthy prints nothing, but every internal
    failure (missing/unparseable checks file, zero checks loaded, no usable
    interpreter) prints a `CHECKER-ERROR:` line on STDOUT. Otherwise a broken
    checker looks exactly like a healthy system to a monitor gate.
  * PROFILE PINNING: `hermes` resolves its profile from $HERMES_HOME. Subprocesses
    run with HERMES_HOME pinned, because running unpinned from another profile's
    context (e.g. an auditor profile, as a cron job does) produces phantom drifts
    on a healthy system. Checks should ALSO pass an explicit `-p <profile>`.

Configure via environment if your layout differs:
    HERMES_HOME      (default: ~/.hermes)
    MAP_CHECKS_FILE  (default: <HERMES_HOME>/ecosystem-map.checks.yaml)
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))
CHECKS_FILE = Path(
    os.environ.get("MAP_CHECKS_FILE", str(HERMES_HOME / "ecosystem-map.checks.yaml"))
)
TIMEOUT_S = 30


def _fail_loud(msg: str, code: int = 2) -> int:
    """Print an error the monitor gate cannot mistake for a healthy system."""
    print(f"CHECKER-ERROR: {msg}")
    return code


def _ensure_yaml() -> None:
    """Guarantee PyYAML is importable, re-execing under an interpreter that has it.

    The python on PATH varies — some Hermes-managed interpreters do NOT ship
    PyYAML while the system python does. An unattended cron job must not depend on
    which one it gets, so probe a few known interpreters and re-exec.
    """
    try:
        import yaml  # noqa: F401
        return
    except ImportError:
        pass

    me = os.path.realpath(sys.executable)
    candidates = [
        "/usr/bin/python3",
        "/bin/python3",
        shutil.which("python3.14"),
        shutil.which("python3.13"),
        shutil.which("python3.12"),
    ]
    tried = []
    for cand in candidates:
        if not cand:
            continue
        real = os.path.realpath(cand)
        if real == me or not os.path.exists(real):
            continue
        tried.append(real)
        probe = subprocess.run([real, "-c", "import yaml"], capture_output=True)
        if probe.returncode == 0:
            os.execv(real, [real, os.path.abspath(__file__)] + sys.argv[1:])

    # STDOUT, not stderr: a monitor gate reads stdout.
    _fail_loud(
        "no python3 with PyYAML found (tried: %s)" % (", ".join(tried) or "none")
    )
    sys.exit(2)


_ensure_yaml()
import yaml  # noqa: E402  (imported after the re-exec guard)


def run_check(cmd: str) -> tuple[str, str | None]:
    """Return (observed_output, error). Never raises."""
    env = dict(os.environ)
    env["HERMES_HOME"] = str(HERMES_HOME)  # see PROFILE PINNING above
    try:
        p = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_S,
            env=env,
        )
        out = (p.stdout or "").strip()
        if not out and p.stderr.strip():
            # Surface stderr only when there is no stdout to compare.
            return "", p.stderr.strip().splitlines()[0][:120]
        return out, None
    except subprocess.TimeoutExpired:
        return "", f"timeout after {TIMEOUT_S}s"
    except Exception as exc:  # noqa: BLE001
        return "", f"{type(exc).__name__}: {exc}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true", help="print PASS lines too")
    ap.add_argument("--exit-code", action="store_true", help="exit 1 when drift found")
    ap.add_argument(
        "--summary",
        action="store_true",
        help="always print a one-line summary even when healthy",
    )
    ap.add_argument("--checks", default=str(CHECKS_FILE), help="path to the checks file")
    args = ap.parse_args()

    checks_path = Path(args.checks)
    if not checks_path.exists():
        return _fail_loud(f"checks file not found: {checks_path}")

    try:
        spec = yaml.safe_load(checks_path.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001
        return _fail_loud(f"cannot parse {checks_path}: {type(exc).__name__}: {exc}")

    checks = spec.get("checks") or []
    if not checks:
        return _fail_loud(f"0 checks loaded from {checks_path}")

    passed = drifted = 0
    drift_lines: list[str] = []
    verbose_lines: list[str] = []

    for c in checks:
        cid = c.get("id", "?")
        claim = c.get("claim", "")
        cmd = c.get("check", "")
        expect = [str(e) for e in (c.get("expect") or [])]

        observed, err = run_check(cmd)
        ok = (observed in expect) if not err else False

        if ok:
            passed += 1
            verbose_lines.append(f"PASS   {cid:28} {observed!r}")
        else:
            drifted += 1
            shown = observed if not err else f"<error: {err}>"
            drift_lines.append(
                f"DRIFT  {cid:28} claim={claim!r} expected={expect} actual={shown!r}"
            )
            verbose_lines.append(f"DRIFT  {cid:28} expected={expect} actual={shown!r}")

    total = len(checks)

    if args.verbose:
        print("\n".join(verbose_lines))
        print()
        print(f"summary: {passed}/{total} pass, {drifted} drift")
        return 1 if (drifted and args.exit_code) else 0

    # Monitor mode: print ONLY drift. Empty output == healthy == no model run.
    if drift_lines:
        print("\n".join(drift_lines))
        print(f"summary: {drifted}/{total} claim(s) drifted")
    elif args.summary:
        print(f"map_check: {passed}/{total} checks pass, no drift")
    # else: deliberately print nothing (monitor-safe).

    return 1 if (drifted and args.exit_code) else 0


if __name__ == "__main__":
    sys.exit(main())
