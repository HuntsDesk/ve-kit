#!/usr/bin/env python3
"""Merge the project's per-developer Claude Code settings into ~/.claude/settings.json.

Run by a HUMAN in a terminal (Claude Code's auto-mode classifier blocks an agent
from editing its own permission config unless the developer has the
self-configuration allow rule, which is one of the things this script installs).

Ships with ve-kit (05-DEVELOPER-SETUP.md). Copy this file and
user-settings.template.json side by side into your repo (docs/claude-code/ is the
convention), fill in every <PLACEHOLDER> in the template, commit both, and have
each developer run the script once after `git pull`.

What it does — and nothing else:
  * backs up ~/.claude/settings.json to ~/.claude/settings.json.bak-<date>
  * sets permissions.defaultMode = "auto"           (only honoured from the user file)
  * sets alwaysThinkingEnabled = true
  * merges modelSettings (per-model effort defaults) — existing keys are kept
  * REPLACES autoMode with the template's (environment + allow, both keep "$defaults")
    unless you already have an autoMode block, in which case it is left alone and
    printed for you to reconcile by hand
  * removes a dead `defaultMode: bypassPermissions` (or `auto`) from the repo's
    .claude/settings.local.json if present (ignored since Claude Code 2.1.257, and
    bypass there makes the session start in Manual)
Everything else in your user file (allow rules, additionalDirectories, plugins,
model) is untouched. Re-runnable.

Usage (from anywhere inside the repo, after `git pull`):
    python3 docs/claude-code/merge-user-settings.py
    python3 docs/claude-code/merge-user-settings.py --dry-run
"""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
from datetime import date

HERE = pathlib.Path(__file__).resolve().parent
TEMPLATE = HERE / "user-settings.template.json"
USER = pathlib.Path.home() / ".claude" / "settings.json"
DRY = "--dry-run" in sys.argv
# A placeholder is <UPPERCASE-LED TEXT> with no nested brackets — the template is
# written to that grammar so a half-filled entry cannot slip past this check.
PLACEHOLDER = re.compile(r"<[A-Z][^<>]*>")


def repo_root() -> pathlib.Path | None:
    """The checkout this script lives in, per git — or None if it is not in one.

    Deliberately NO fallback to the working directory: run from $HOME outside a
    repo, a cwd fallback would resolve LOCAL to ~/.claude/settings.local.json — a
    real user-level Claude Code file — and edit it. When git cannot answer, the
    local-settings step is skipped instead.
    """
    try:
        out = subprocess.run(
            ["git", "-C", str(HERE), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return pathlib.Path(out) if out else None
    except (OSError, subprocess.CalledProcessError):
        return None


ROOT = repo_root()
LOCAL = ROOT / ".claude" / "settings.local.json" if ROOT else None


def load(p: pathlib.Path) -> dict:
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR: {p} is not valid JSON ({e}). Fix it first; nothing was changed.")


def save(p: pathlib.Path, d: dict) -> None:
    if DRY:
        print(f"[dry-run] would write {p}")
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(d, indent=2) + "\n")


def unfilled_placeholders(tmpl: dict) -> list[str]:
    """Every <PLACEHOLDER> still present in the template's environment entries."""
    found: list[str] = []
    for entry in tmpl.get("autoMode", {}).get("environment", []):
        found.extend(PLACEHOLDER.findall(entry))
    return found


def main() -> None:
    tmpl = load(TEMPLATE)
    if not tmpl:
        sys.exit(f"ERROR: template not found at {TEMPLATE} — keep it next to this script.")

    left = unfilled_placeholders(tmpl)
    if left:
        sample = ", ".join(sorted(set(left))[:6])
        sys.exit(
            f"ERROR: {TEMPLATE.name} still has {len(left)} unfilled placeholder(s) "
            f"(e.g. {sample}). Describe YOUR project in autoMode.environment first — "
            "the classifier reads those entries as prose, and a placeholder teaches it nothing."
        )

    user = load(USER)
    if USER.exists() and not DRY:
        bak = USER.with_name(f"{USER.name}.bak-{date.today().isoformat()}")
        if bak.exists():
            print(f"backup already exists, kept as the pre-merge original: {bak}")
        else:
            shutil.copyfile(USER, bak)
            print(f"backup: {bak}")

    changes: list[str] = []

    perms = user.setdefault("permissions", {})
    if perms.get("defaultMode") != "auto":
        changes.append(f"permissions.defaultMode: {perms.get('defaultMode')!r} -> 'auto'")
        perms["defaultMode"] = "auto"

    if user.get("alwaysThinkingEnabled") is not True:
        changes.append("alwaysThinkingEnabled -> true")
        user["alwaysThinkingEnabled"] = True

    ms = user.setdefault("modelSettings", {})
    for model, cfg in tmpl.get("modelSettings", {}).items():
        if model not in ms:
            ms[model] = cfg
            changes.append(f"modelSettings[{model}] added ({cfg})")

    if "autoMode" in user:
        print("NOTE: you already have an autoMode block — left as is. Reconcile by hand against the template:")
        print(json.dumps(user["autoMode"], indent=2)[:1500])
    else:
        user["autoMode"] = tmpl["autoMode"]
        env_n = len(tmpl["autoMode"].get("environment", []))
        changes.append(f"autoMode added ({env_n} environment entries + self-configuration allow rule; $defaults kept)")

    save(USER, user)

    # Dead defaultMode in the gitignored project-local file.
    if LOCAL is None:
        print("note: not inside a git checkout, so .claude/settings.local.json was not checked")
    elif LOCAL.exists():
        local = load(LOCAL)
        lp = local.get("permissions", {})
        if lp.get("defaultMode") in ("bypassPermissions", "auto"):
            changes.append(f"{LOCAL}: removed dead defaultMode {lp['defaultMode']!r}")
            del lp["defaultMode"]
            save(LOCAL, local)

    print("\n".join(f"  - {c}" for c in changes) if changes else "  nothing to change — already up to date")
    if not DRY:
        # Verify what we wrote parses and carries the expected keys.
        chk = load(USER)
        assert chk["permissions"]["defaultMode"] == "auto"
        if "environment" not in chk.get("autoMode", {}):
            print("WARNING: your existing autoMode block has no environment entries — copy the template's "
                  "autoMode.environment into ~/.claude/settings.json by hand, keeping \"$defaults\" first.")
        print("\nOK. Next: close every Claude Code window, reopen, then run:  claude auto-mode config | head -40")


if __name__ == "__main__":
    main()
