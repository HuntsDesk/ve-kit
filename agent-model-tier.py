#!/usr/bin/env python3
"""Apply / verify the model+effort tier of every .claude/agents/*.md file.

The manifest .claude/agent-model-tiers.json is the source of truth. It records TWO
assignments per agent -- `preferred` (the review-checklist.md rubric's output) and
`fallback` (the degraded-capacity assignment) -- plus a `restore_tier` for partial
restores.

    scripts/agent-model-tier.py status
    scripts/agent-model-tier.py check
    scripts/agent-model-tier.py apply fallback
    scripts/agent-model-tier.py apply preferred
    scripts/agent-model-tier.py apply preferred --tier 1     # partial restore
    scripts/agent-model-tier.py apply preferred --dry-run

WHY A SCRIPT AND NOT AN AGENT. The restore has to reproduce a recorded assignment
exactly. An LLM re-deriving "which agents go back to the preferred model" months from
now returns a plausible roster with no error anywhere. The judgement lives in the
manifest (written once, reviewed); the application is mechanical.

SETUP (ve-kit). Drop this file anywhere in your repo (scripts/ is the convention) and
copy agent-model-tiers.template.json to .claude/agent-model-tiers.json, then give every
.claude/agents/*.md file an entry -- `check` refuses to run until the manifest and the
directory agree, in both directions.

FAIL-LOUD CONTRACT. Every path that could report success while having done nothing is
an explicit error instead:
  - manifest agent with no file on disk            -> error, exit 2
  - file on disk with no manifest entry            -> error, exit 2
  - zero agents matched (an empty sweep)           -> error, exit 2
  - `model:` / `effort:` line missing from a file  -> error, exit 2 (never silently added
                                                      to the body or silently skipped)
  - `check` drift                                  -> exit 1, every offender named
Only an actually-verified match exits 0. `apply` re-runs the full check afterwards and
propagates its exit code, so "applied" always means "verified applied".
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

def _repo_root() -> Path:
    """The checkout this script lives in, per git. No cwd fallback: a wrong guess
    would edit the wrong .claude/agents/ silently, which is the exact failure this
    script exists to prevent."""
    import subprocess

    try:
        out = subprocess.run(
            ["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit(f"ERROR: agent-model-tier.py must live inside a git checkout ({e})")
    if not out:
        sys.exit("ERROR: git rev-parse returned no repo root")
    return Path(out)


REPO = _repo_root()
MANIFEST = REPO / ".claude" / "agent-model-tiers.json"
AGENTS_DIR = REPO / ".claude" / "agents"

MODES = ("preferred", "fallback")
FRONTMATTER_FENCE = "---"


class TierError(Exception):
    """Anything that must stop the run rather than degrade quietly."""


# --------------------------------------------------------------------------- io


def load_manifest() -> dict:
    if not MANIFEST.exists():
        raise TierError(f"manifest not found: {MANIFEST}")
    data = json.loads(MANIFEST.read_text())
    if data.get("mode") not in MODES:
        raise TierError(f"manifest `mode` must be one of {MODES}, got {data.get('mode')!r}")
    agents = data.get("agents")
    if not isinstance(agents, dict) or not agents:
        raise TierError("manifest `agents` is missing or empty -- refusing to run")
    for name, entry in agents.items():
        for mode in MODES:
            spec = entry.get(mode)
            if not isinstance(spec, dict) or "model" not in spec or "effort" not in spec:
                raise TierError(
                    f"{name}: `{mode}` must be an object with both `model` and `effort` "
                    "(use null for effort to mean 'omit the line')"
                )
    return data


def split_frontmatter(path: Path) -> tuple[list[str], list[str]]:
    """Return (frontmatter_lines, rest_lines). Body is never handed to the writer."""
    lines = path.read_text().splitlines(keepends=True)
    if not lines or lines[0].rstrip("\n") != FRONTMATTER_FENCE:
        raise TierError(f"{path.name}: no opening `---` frontmatter fence on line 1")
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n") == FRONTMATTER_FENCE:
            return lines[: i + 1], lines[i + 1 :]
    raise TierError(f"{path.name}: frontmatter fence opened but never closed")


def read_field(front: list[str], field: str) -> str | None:
    pat = re.compile(rf"^{re.escape(field)}:\s*(\S+)\s*$")
    for line in front:
        m = pat.match(line)
        if m:
            return m.group(1)
    return None


def write_field(front: list[str], field: str, value: str | None, agent: str) -> list[str]:
    """Rewrite `field` in place. Never inserts, never appends -- see the fail-loud contract.

    A missing line is an error rather than an insertion because we cannot know whether
    frontmatter or body owns the position, and guessing wrong writes YAML into the prompt.
    """
    pat = re.compile(rf"^{re.escape(field)}:\s*\S+\s*$")
    hits = [i for i, line in enumerate(front) if pat.match(line)]

    if value is None:
        if hits:
            raise TierError(
                f"{agent}: manifest says `{field}` should be ABSENT (inherit), but the file "
                f"has `{front[hits[0]].strip()}`. Remove it by hand -- this script will not "
                "delete frontmatter lines."
            )
        return front

    if not hits:
        raise TierError(
            f"{agent}: no `{field}:` line in frontmatter. Add it by hand "
            f"(`{field}: {value}`) -- this script only rewrites existing lines, so it "
            "cannot accidentally write YAML into the prompt body."
        )
    if len(hits) > 1:
        raise TierError(f"{agent}: {len(hits)} `{field}:` lines in frontmatter -- ambiguous")

    out = list(front)
    out[hits[0]] = f"{field}: {value}\n"
    return out


# ---------------------------------------------------------------------- compare


def agent_files() -> dict[str, Path]:
    return {p.stem: p for p in sorted(AGENTS_DIR.glob("*.md")) if p.stem != "README"}


def reconcile(manifest: dict) -> dict[str, Path]:
    """Manifest keys and files on disk must be the same set. Either direction is an error."""
    files = agent_files()
    declared = set(manifest["agents"])
    on_disk = set(files)

    missing_file = sorted(declared - on_disk)
    missing_entry = sorted(on_disk - declared)
    problems = []
    if missing_file:
        problems.append(
            "in the manifest but no file on disk: " + ", ".join(missing_file)
        )
    if missing_entry:
        problems.append(
            "on disk but not in the manifest (add an entry, same commit): "
            + ", ".join(missing_entry)
        )
    if problems:
        raise TierError("manifest/roster mismatch -- " + "; ".join(problems))
    if not files:
        raise TierError(f"no agent files found under {AGENTS_DIR} -- refusing to report success")
    return files


def observed(path: Path) -> tuple[str | None, str | None]:
    front, _ = split_frontmatter(path)
    return read_field(front, "model"), read_field(front, "effort")


def select(manifest: dict, tiers: set[int] | None) -> list[str]:
    """Agent names in scope. An empty scope is an ERROR, never a quiet pass.

    The `scoped == 0` guard used to live in cmd_apply alone, so `check --tier 9`
    exited 0 with "OK" — a false green sitting inside the documented partial-restore
    loop ("re-run check after each tier"). Both verbs share this now.
    """
    names = [
        n for n, e in sorted(manifest["agents"].items())
        if tiers is None or e.get("restore_tier") in tiers
    ]
    if not names:
        raise TierError(
            f"restore_tier filter {sorted(tiers or [])} matched 0 agents -- "
            "an empty scope is never a success. Valid tiers: "
            f"{sorted(t for t in {e.get('restore_tier') for e in manifest['agents'].values()} if t is not None)}"
        )
    return names


def drift(manifest: dict, mode: str, tiers: set[int] | None) -> list[str]:
    files = reconcile(manifest)
    rows = []
    for name in select(manifest, tiers):
        want = manifest["agents"][name][mode]
        got_model, got_effort = observed(files[name])
        if got_model != want["model"] or got_effort != want["effort"]:
            rows.append(
                f"  {name}: have model={got_model} effort={got_effort} "
                f"-> want model={want['model']} effort={want['effort']}"
            )
    return rows


# ----------------------------------------------------------------------- verbs


def cmd_status(manifest: dict) -> int:
    files = reconcile(manifest)
    mode = manifest["mode"]
    print(f"declared mode : {mode}")
    print(f"set           : {manifest.get('mode_set_at')} by {manifest.get('mode_set_by')}")
    print(f"reason        : {manifest.get('mode_reason')}")
    print(f"restore when  : {manifest.get('restore_when')}")
    print(f"agents        : {len(files)}")

    counts: dict[str, int] = {}
    for name in manifest["agents"]:
        m, e = observed(files[name])
        counts[f"{m}/{e or 'inherit'}"] = counts.get(f"{m}/{e or 'inherit'}", 0) + 1
    print("live on disk  : " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    rows = drift(manifest, mode, None)
    if rows:
        print(f"\nDRIFT vs declared mode `{mode}` ({len(rows)}):")
        print("\n".join(rows))
        return 1
    print(f"\nno drift -- every agent matches its `{mode}` assignment")
    return 0


def cmd_check(manifest: dict, tiers: set[int] | None, mode: str | None = None) -> int:
    """`mode` overrides the declared mode -- for verifying a PARTIAL restore, whose
    target is not yet the declared state (see cmd_apply)."""
    declared = manifest["mode"]
    mode = mode or declared
    rows = drift(manifest, mode, tiers)
    scope = f" (restore_tier {sorted(tiers)})" if tiers else ""
    if mode != declared:
        scope += f" [verifying against `{mode}`; declared mode is still `{declared}`]"
    label = "declared mode" if mode == declared else "mode"
    if rows:
        print(f"DRIFT vs {label} `{mode}`{scope} -- {len(rows)} agent(s):", file=sys.stderr)
        print("\n".join(rows), file=sys.stderr)
        return 1
    print(f"OK -- every agent matches its `{mode}` assignment{scope}")
    return 0


def cmd_apply(manifest: dict, mode: str, tiers: set[int] | None, dry_run: bool) -> int:
    """TWO-PHASE: plan every file (raising before any write), then write.

    A single-pass loop that wrote as it went left the roster HALF-FLIPPED when a
    late file was malformed -- 24 of 40 rewritten, manifest `mode` unmoved, and an
    error message ("add it by hand") that said nothing about the 24. That is a worse
    state than either endpoint, because the fleet then straddles two models with
    nothing recording it. Planning first makes a malformed file a no-op instead.
    """
    files = reconcile(manifest)
    scoped = select(manifest, tiers)

    planned: list[tuple[Path, str]] = []   # (path, full new text)
    changed: list[str] = []
    for name in scoped:
        want = manifest["agents"][name][mode]
        path = files[name]
        front, body = split_frontmatter(path)
        got_model, got_effort = read_field(front, "model"), read_field(front, "effort")
        if got_model == want["model"] and got_effort == want["effort"]:
            continue
        # write_field raises here, during planning, before anything hits disk.
        front = write_field(front, "model", want["model"], name)
        front = write_field(front, "effort", want["effort"], name)
        planned.append((path, "".join(front + body)))
        changed.append(
            f"  {name}: {got_model}/{got_effort or 'inherit'} "
            f"-> {want['model']}/{want['effort'] or 'inherit'}"
        )

    if not dry_run:
        for path, text in planned:
            path.write_text(text)

    verb = "would change" if dry_run else "changed"
    print(f"mode `{mode}`, {len(scoped)} agent(s) in scope, {verb} {len(changed)}:")
    print("\n".join(changed) if changed else "  (already in the target state)")

    if dry_run:
        return 0

    # Only record the mode once the full roster is on it; a partial restore leaves the
    # declared mode alone: a partial restore is not the declared state. A plain
    # `check` (against the declared mode) therefore flags the RESTORED agents until
    # the full apply runs -- verify a partial step with `check --mode <target> --tier N`.
    if tiers is None and manifest["mode"] != mode:
        raw = MANIFEST.read_text()
        new = re.sub(r'("mode":\s*)"(?:preferred|fallback)"', rf'\1"{mode}"', raw, count=1)
        if new == raw:
            raise TierError("could not rewrite `mode` in the manifest -- edit it by hand")
        MANIFEST.write_text(new)
        print(f"manifest `mode` -> {mode}")
        manifest = load_manifest()

    print("\nverifying...")
    if tiers is None:
        return cmd_check(manifest, tiers)
    # Tier-scoped apply: verify the SCOPED agents against the mode just applied --
    # not the stale declared mode, which made a fully successful partial restore
    # exit 1 and name the agents it had just restored (found 2026-09-12) -- and
    # REPORT, not fail on, the agents outside the scope still on the old tier.
    rc = cmd_check(manifest, tiers, mode=mode)
    files = reconcile(manifest)
    still = [
        n for n in manifest["agents"] if n not in scoped
        and observed(files[n]) != (manifest["agents"][n][mode]["model"], manifest["agents"][n][mode]["effort"])
    ]
    print(f"{len(still)} agent(s) outside restore_tier {sorted(tiers)} still on the old tier: {', '.join(still) or '-'}")
    print(f"manifest `mode` stays `{manifest['mode']}` until a full `apply {mode}` (no --tier) runs; "
          f"`check --mode {mode} --tier N` verifies partial progress.")
    return rc


# ------------------------------------------------------------------------ main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status", help="show declared mode, live counts, and any drift")

    p_check = sub.add_parser("check", help="exit 1 if any agent drifts from the declared mode")
    p_check.add_argument("--tier", type=int, action="append", help="limit to a restore_tier (repeatable)")
    p_check.add_argument("--mode", choices=MODES, help="verify against this mode instead of the declared one (partial restores)")

    p_apply = sub.add_parser("apply", help="write the frontmatter for a mode")
    p_apply.add_argument("mode", choices=MODES)
    p_apply.add_argument("--tier", type=int, action="append", help="limit to a restore_tier (repeatable)")
    p_apply.add_argument("--dry-run", action="store_true")

    args = ap.parse_args()
    tiers = set(args.tier) if getattr(args, "tier", None) else None

    try:
        manifest = load_manifest()
        if args.cmd == "status":
            return cmd_status(manifest)
        if args.cmd == "check":
            return cmd_check(manifest, tiers, mode=args.mode)
        return cmd_apply(manifest, args.mode, tiers, args.dry_run)
    except TierError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
