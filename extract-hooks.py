#!/usr/bin/env python3
"""Extract the kit's hook scripts and their test suites out of 01-BOOTSTRAP.md.

The kit ships its hooks as fenced templates under `### File: .claude/hooks/<name>`
headings inside 01-BOOTSTRAP.md, because the bootstrap agent writes them into YOUR
project. That means there is no loose `review-gate.sh` to run, diff, or test. This
script materialises them:

    python3 extract-hooks.py --project /path/to/project            # hooks + suites
    python3 extract-hooks.py --project /tmp/scratch --settings      # + .claude/settings.json
    python3 extract-hooks.py --list                                 # names only, writes nothing

It writes `<project>/.claude/hooks/<name>` (mode 755) for every block, and with
`--settings` also writes the Phase 6 hook registration to `<project>/.claude/settings.json`.
It never overwrites an existing file unless `--force` is given.

It FAILS LOUDLY (non-zero exit, named reason on stderr) rather than writing a partial
or empty set:

    exit 2  usage / bootstrap file not found / target not writable
    exit 3  a fence is unterminated, or a `### File:` heading has no fenced block
    exit 4  fewer hooks or suites than expected (see --min-hooks / --min-suites)
    exit 5  an extracted script is not a script (no shebang) or fails `bash -n`
    exit 6  a target file already exists and --force was not given
    exit 7  --settings: the registration block is missing, ambiguous, or not valid JSON

The last stdout line on success is `HOOKS=<n> SUITES=<n>` (plus ` SETTINGS=written`
with --settings). Stdlib only; Python 3.6+.
"""
import argparse
import json
import os
import re
import subprocess
import sys

# Floors, not exact counts: the kit grows. A snapshot that yields FEWER than this has
# lost blocks (a broken fence swallowed them, or a heading was renamed) and must not be
# trusted. Raise these when the kit adds hooks; never lower them to make a run pass.
MIN_HOOKS = 11
MIN_SUITES = 11  # since 2026-09-21 every shipped hook has a suite

HEADING_RE = re.compile(r"^### File: `(?P<target>[^`]+)`")
FENCE_RE = re.compile(r"^(?P<ticks>`{3,})(?P<info>.*)$")
HOOK_PREFIX = ".claude/hooks/"
SETTINGS_TARGET = ".claude/settings.json"


class ExtractError(Exception):
    def __init__(self, code, message):
        Exception.__init__(self, message)
        self.code = code


def parse_blocks(lines):
    """Walk the file once with a fence state machine.

    Returns (file_blocks, json_blocks):
      file_blocks: list of (target, heading_lineno, info, body_lines) -- the FIRST fenced
                   block after each `### File:` heading that sits outside any fence.
      json_blocks: list of (open_lineno, body_text) for every top-level ```json fence.

    A fence opened with N backticks closes only on a line of >= N backticks and nothing
    else, so a ````markdown block that itself contains ```bash examples (and `### File:`
    lines) is skipped as one unit instead of leaking false headings.
    """
    file_blocks = []
    json_blocks = []
    pending = None          # (target, lineno) awaiting its first fence
    fence = None            # (tick_count, info, open_lineno, body_lines)
    for idx, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        m = FENCE_RE.match(line)
        if fence is not None:
            ticks, info, open_no, body = fence
            if m and len(m.group("ticks")) >= ticks and m.group("info").strip() == "":
                if pending is not None:
                    file_blocks.append((pending[0], pending[1], info, body))
                    pending = None
                if info.strip().lower() == "json":
                    json_blocks.append((open_no, "\n".join(body) + "\n"))
                fence = None
            else:
                body.append(line)
            continue
        if m:
            fence = (len(m.group("ticks")), m.group("info"), idx, [])
            continue
        h = HEADING_RE.match(line)
        if h:
            if pending is not None:
                raise ExtractError(3, "heading at line %d (`%s`) has no fenced block before the next "
                                      "`### File:` heading at line %d" % (pending[1], pending[0], idx))
            pending = (h.group("target"), idx)
    if fence is not None:
        raise ExtractError(3, "unterminated fence: opened at line %d with %d backticks (info %r) and never "
                              "closed" % (fence[2], fence[0], fence[1]))
    if pending is not None:
        raise ExtractError(3, "heading at line %d (`%s`) has no fenced block before end of file"
                           % (pending[1], pending[0]))
    return file_blocks, json_blocks


def find_settings_json(json_blocks):
    """The Phase 6 registration: the one ```json block that has a top-level "hooks" object
    naming at least one .claude/hooks/ command. Exactly one must qualify."""
    hits = []
    for open_no, text in json_blocks:
        try:
            data = json.loads(text)
        except ValueError:
            continue
        if isinstance(data, dict) and isinstance(data.get("hooks"), dict) and HOOK_PREFIX in text:
            hits.append((open_no, data))
    if not hits:
        raise ExtractError(7, "no ```json block with a top-level \"hooks\" object registering "
                              ".claude/hooks/ commands was found")
    if len(hits) > 1:
        raise ExtractError(7, "registration block is ambiguous: %d candidate ```json blocks (lines %s)"
                           % (len(hits), ", ".join(str(h[0]) for h in hits)))
    return hits[0][1]


def bash_syntax_ok(script_file):
    """(ok, detail). ok is None when bash is not available to ask."""
    try:
        proc = subprocess.run(["bash", "-n", script_file], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True)
    except OSError:
        return None, "bash not found"
    return proc.returncode == 0, proc.stderr.strip()


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(
        description="Extract the hook + test-suite templates from 01-BOOTSTRAP.md into a project.",
        epilog="Success prints HOOKS=<n> SUITES=<n> as the last line. Any failure is a non-zero exit "
               "with `extract-hooks: FAILED (<reason>)` on stderr -- nothing is written on a parse failure.")
    ap.add_argument("--bootstrap", default=os.path.join(here, "01-BOOTSTRAP.md"),
                    help="path to 01-BOOTSTRAP.md (default: the one beside this script)")
    ap.add_argument("--project", help="project root; files land in <project>/.claude/hooks/")
    ap.add_argument("--settings", action="store_true",
                    help="also write the Phase 6 hook registration to <project>/.claude/settings.json")
    ap.add_argument("--force", action="store_true", help="overwrite files that already exist")
    ap.add_argument("--list", action="store_true", help="print the block names and exit; writes nothing")
    ap.add_argument("--min-hooks", type=int, default=MIN_HOOKS,
                    help="fail if fewer hook blocks than this are found (default %d)" % MIN_HOOKS)
    ap.add_argument("--min-suites", type=int, default=MIN_SUITES,
                    help="fail if fewer test-*.sh blocks than this are found (default %d)" % MIN_SUITES)
    args = ap.parse_args(argv)

    if not args.list and not args.project:
        ap.error("--project is required (or use --list)")

    try:
        try:
            with open(args.bootstrap, encoding="utf-8") as fh:
                lines = fh.readlines()
        except OSError as exc:
            raise ExtractError(2, "cannot read bootstrap file %s: %s" % (args.bootstrap, exc))

        file_blocks, json_blocks = parse_blocks(lines)
        scripts = []
        seen = {}
        for target, lineno, info, body in file_blocks:
            if not target.startswith(HOOK_PREFIX):
                continue
            name = target[len(HOOK_PREFIX):]
            if "/" in name or name in ("", ".", ".."):
                raise ExtractError(3, "heading at line %d names an unsafe hook path: %r" % (lineno, target))
            if name in seen:
                raise ExtractError(3, "duplicate `### File:` heading for %s (lines %d and %d)"
                                   % (target, seen[name], lineno))
            seen[name] = lineno
            scripts.append((name, lineno, body))

        suites = [s for s in scripts if s[0].startswith("test-")]
        hooks = [s for s in scripts if not s[0].startswith("test-")]
        if len(hooks) < args.min_hooks or len(suites) < args.min_suites:
            raise ExtractError(4, "found HOOKS=%d SUITES=%d, expected at least HOOKS=%d SUITES=%d -- a fence "
                                  "or heading in %s has changed shape"
                               % (len(hooks), len(suites), args.min_hooks, args.min_suites,
                                  os.path.basename(args.bootstrap)))
        for name, lineno, body in scripts:
            if not body or not body[0].startswith("#!"):
                raise ExtractError(5, "%s (heading line %d): first fenced block does not start with a "
                                      "shebang -- wrong block captured" % (name, lineno))

        settings = find_settings_json(json_blocks) if args.settings else None

        if args.list:
            for name, lineno, body in scripts:
                kind = "suite" if name.startswith("test-") else "hook"
                print("%s\t%s\tline=%d\tlines=%d" % (kind, name, lineno, len(body)))
            print("HOOKS=%d SUITES=%d" % (len(hooks), len(suites)))
            return 0

        hooks_dir = os.path.join(args.project, ".claude", "hooks")
        settings_file = os.path.join(args.project, SETTINGS_TARGET)
        targets = [os.path.join(hooks_dir, s[0]) for s in scripts]
        if settings is not None:
            targets.append(settings_file)
        if not args.force:
            clash = [t for t in targets if os.path.exists(t)]
            if clash:
                raise ExtractError(6, "%d target file(s) already exist (first: %s) -- pass --force to "
                                      "overwrite" % (len(clash), clash[0]))
        try:
            os.makedirs(hooks_dir, exist_ok=True)
            for name, lineno, body in scripts:
                dest = os.path.join(hooks_dir, name)
                with open(dest, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write("\n".join(body) + "\n")
                os.chmod(dest, 0o755)
            if settings is not None:
                with open(settings_file, "w", encoding="utf-8", newline="\n") as fh:
                    json.dump(settings, fh, indent=2)
                    fh.write("\n")
        except OSError as exc:
            raise ExtractError(2, "cannot write into %s: %s" % (args.project, exc))

        bash_seen = True
        for name, lineno, body in scripts:
            ok, detail = bash_syntax_ok(os.path.join(hooks_dir, name))
            if ok is None:
                bash_seen = False
                break
            if not ok:
                raise ExtractError(5, "%s (heading line %d) fails `bash -n`: %s" % (name, lineno, detail))
        if not bash_seen:
            print("extract-hooks: WARN bash not found, syntax check SKIPPED (files were written)",
                  file=sys.stderr)

        for name, lineno, body in scripts:
            print("wrote .claude/hooks/%s" % name)
        tail = "HOOKS=%d SUITES=%d" % (len(hooks), len(suites))
        if settings is not None:
            print("wrote %s" % SETTINGS_TARGET)
            tail += " SETTINGS=written"
        print(tail)
        return 0
    except ExtractError as exc:
        print("extract-hooks: FAILED (%s)" % exc, file=sys.stderr)
        return exc.code


if __name__ == "__main__":
    sys.exit(main())
