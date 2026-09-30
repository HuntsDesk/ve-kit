#!/bin/bash
# doctor.sh -- verify that the kit's hooks are actually ARMED in this project.
#
# Why this exists: every hook in the kit FAILS OPEN. No working Python interpreter,
# a hook file that is not executable, or a hook that was never registered all look
# exactly like "the gate passed" -- no error, no warning, not even a telemetry row.
# So "my commits go through" is not evidence the gates work. This script is.
#
# Run it from the root of a bootstrapped project:
#
#     bash doctor.sh                 # check everything, run every test-*.sh suite
#     bash doctor.sh --no-suites     # installation checks only (fast)
#     bash doctor.sh --strict        # WARN and SKIPPED also fail (what CI uses)
#
# Every check prints ONE line:   KEY=ok | KEY=WARN(<why>) | KEY=FAIL(<why>) | KEY=SKIPPED(<why>)
#
#   ok       the check ran and passed
#   FAIL     the check ran and found a problem                     -> exit 1
#   WARN     works, but a gate is weaker than you think            -> exit 0 (1 with --strict)
#   SKIPPED  the check COULD NOT RUN. Never read this as a pass.   -> exit 0 (1 with --strict)
#
# The last line is always DOCTOR=ok|WARN|FAIL with the counts. Exit 2 is a usage error.
# No network calls, nothing written outside a temp dir, nothing in your project is modified.
set -u

PROJECT=""; HOOKS_DIR=""; SETTINGS=""; RUN_SUITES=1; STRICT=0; VERBOSE=0; SUITE_TIMEOUT=300
SELF_CHECK=0; BOOTSTRAP=""

usage() {
  cat <<'USAGE'
Usage: bash doctor.sh [options]

  --project DIR        project root (default: the git top-level of the current dir, else the current dir)
  --hooks-dir DIR      where the hook scripts live (default: <project>/.claude/hooks)
  --settings FILE      hook registration file (default: <project>/.claude/settings.json;
                       <project>/.claude/settings.local.json is read too when present)
  --no-suites          skip running the test-*.sh suites
  --suite-timeout SEC  per-suite wall clock before it is killed and reported FAIL (default 300)
  --strict             treat WARN and SKIPPED as failures (exit 1). Use this in CI.
  --verbose            print each suite's full output, not just its failing lines
  -h, --help           this text

Maintainer mode (run from the kit, not from a project):
  --self-check         compare THIS script's hook roster with the hooks 01-BOOTSTRAP.md ships
                       (via extract-hooks.py --list), in both directions, and check that the
                       suite named for each hook is shipped too. Prints
                       TABLE_VS_BOOTSTRAP=ok|FAIL(..); exit 0 = same set, 1 = they differ,
                       2 = the comparison could not run. Checks nothing in a project.
  --bootstrap FILE     with --self-check: the bootstrap file to compare against
                       (default: 01-BOOTSTRAP.md beside this script)

Output: one KEY=ok|WARN(..)|FAIL(..)|SKIPPED(..) line per check, then DOCTOR=<verdict>.
Exit:   0 = no FAIL (WARN/SKIPPED are listed)   1 = at least one FAIL
        2 = usage error, or doctor itself could not run (never a verdict on your hooks)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)       [ $# -ge 2 ] || { echo "doctor: --project needs a value" >&2; exit 2; }; PROJECT="$2"; shift 2 ;;
    --hooks-dir)     [ $# -ge 2 ] || { echo "doctor: --hooks-dir needs a value" >&2; exit 2; }; HOOKS_DIR="$2"; shift 2 ;;
    --settings)      [ $# -ge 2 ] || { echo "doctor: --settings needs a value" >&2; exit 2; }; SETTINGS="$2"; shift 2 ;;
    --suite-timeout) [ $# -ge 2 ] || { echo "doctor: --suite-timeout needs a value" >&2; exit 2; }; SUITE_TIMEOUT="$2"; shift 2 ;;
    --bootstrap)     [ $# -ge 2 ] || { echo "doctor: --bootstrap needs a value" >&2; exit 2; }; BOOTSTRAP="$2"; shift 2 ;;
    --self-check)    SELF_CHECK=1; shift ;;
    --no-suites)     RUN_SUITES=0; shift ;;
    --strict)        STRICT=1; shift ;;
    --verbose)       VERBOSE=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "doctor: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$SUITE_TIMEOUT" in ''|*[!0-9]*) echo "doctor: --suite-timeout must be a whole number of seconds" >&2; exit 2 ;; esac

# A probe that cannot run must say so, never guess: without these every count below would
# come back empty and an empty count must not be allowed to read as "0 failed".
MISSING_TOOLS=""
for tool in awk grep sed head tail mktemp dirname basename sleep env rm; do
  command -v "$tool" >/dev/null 2>&1 || MISSING_TOOLS="$MISSING_TOOLS $tool"
done
if [ -n "$MISSING_TOOLS" ]; then
  echo "DOCTOR=FAIL(cannot run: missing from PATH:$MISSING_TOOLS -- this is NOT a verdict on your hooks)"
  exit 2
fi

if [ -z "$PROJECT" ]; then
  PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || PROJECT=""
  [ -n "$PROJECT" ] || PROJECT="$PWD"
fi
[ -d "$PROJECT" ] || { echo "doctor: project dir not found: $PROJECT" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
[ -n "$HOOKS_DIR" ] || HOOKS_DIR="$PROJECT/.claude/hooks"
[ -n "$SETTINGS" ]  || SETTINGS="$PROJECT/.claude/settings.json"
SETTINGS_LOCAL="$(dirname "$SETTINGS")/settings.local.json"

# The kit's hook roster: <file>|<required|optional>|<Event:Tool+Tool,Event:...>|<its test suite>
# An empty tool list means the event takes no matcher. `optional` follows the labels in
# 01-BOOTSTRAP.md ("recommended" / "optional"): such a hook may be absent -- but if it is
# REGISTERED and absent, that is a FAIL, because a hook that cannot launch never blocks.
#
# This table is hand-kept, so it is CHECKED, not trusted. Two mechanisms, both in
# .github/workflows/gates.yml, and both proven there by a planted defect:
#   - `doctor.sh --self-check` fails when the set of hooks here differs from the set
#     01-BOOTSTRAP.md ships, in EITHER direction (a 12th hook added there but not here
#     would otherwise never be checked by this script, and CI would stay green), and
#     when a hook's suite (4th column) is not among the suites 01-BOOTSTRAP.md ships --
#     so "every hook ships a suite" is a checked claim, not a sentence in a README;
#   - CI regenerates settings.json from 01-BOOTSTRAP.md and runs this script against it,
#     so an Event:Tool expectation here that the template does not register turns REG_ red.
# Not covered: an EXTRA event registered by the template for a hook already listed here.
HOOK_TABLE='block-todowrite.sh|required|PreToolUse:TodoWrite|test-block-todowrite.sh
session-handoff.sh|required|SessionStart:|test-session-handoff.sh
post-compact-recovery.sh|required|PostCompact:|test-post-compact-recovery.sh
review-gate.sh|required|PreToolUse:Bash|test-review-gate.sh
stop-compliance-check.sh|required|Stop:|test-stop-hook.sh
fact-gate.sh|required|PreToolUse:Edit+Write+MultiEdit|test-fact-gate.sh
protected-files-gate.sh|required|PreToolUse:Edit+Write+MultiEdit|test-protected-files-gate.sh
gitleaks-gate.sh|optional|PreToolUse:Bash|test-gitleaks-gate.sh
bash-edit-telemetry.sh|optional|PreToolUse:Bash,PostToolUse:Bash|test-bash-edit-telemetry.sh
instructions-loaded-telemetry.sh|optional|InstructionsLoaded:|test-instructions-loaded-telemetry.sh
telemetry-ingest.sh|optional|SessionStart:,Stop:|test-telemetry-ingest.sh'

if [ "$SELF_CHECK" = 1 ]; then
  HERE="$(cd "$(dirname "$0")" && pwd)"
  [ -n "$BOOTSTRAP" ] || BOOTSTRAP="$HERE/01-BOOTSTRAP.md"
  SC_PY=""
  for candidate in python3 python "py -3"; do
    if $candidate -c "import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)" >/dev/null 2>&1; then SC_PY="$candidate"; break; fi
  done
  if [ -z "$SC_PY" ]; then echo "TABLE_VS_BOOTSTRAP=SKIPPED(could not run: no Python interpreter for extract-hooks.py)"; exit 2; fi
  if [ ! -f "$HERE/extract-hooks.py" ]; then echo "TABLE_VS_BOOTSTRAP=SKIPPED(could not run: extract-hooks.py is not beside doctor.sh)"; exit 2; fi
  # Floors off: this compares SETS, and a short list must show up as a named difference
  # rather than as the extractor refusing to answer.
  SC_LIST="$($SC_PY "$HERE/extract-hooks.py" --bootstrap "$BOOTSTRAP" --list --min-hooks 0 --min-suites 0 2>&1)"; SC_RC=$?
  if [ "$SC_RC" != 0 ]; then
    echo "TABLE_VS_BOOTSTRAP=SKIPPED(could not run: extract-hooks.py exited $SC_RC: $(printf '%s' "$SC_LIST" | tail -n 1))"; exit 2
  fi
  SC_SHIPPED="$(printf '%s\n' "$SC_LIST" | awk -F'\t' '$1=="hook"{print $2}' | sort -u)"
  SC_TABLE="$(printf '%s\n' "$HOOK_TABLE" | awk -F'|' 'NF>=3{print $1}' | sort -u)"
  if [ -z "$SC_SHIPPED" ] || [ -z "$SC_TABLE" ]; then
    echo "TABLE_VS_BOOTSTRAP=SKIPPED(could not run: one side of the comparison is empty -- shipped='$(echo $SC_SHIPPED)' table='$(echo $SC_TABLE)')"; exit 2
  fi
  SC_SUITES="$(printf '%s\n' "$SC_LIST" | awk -F'\t' '$1=="suite"{print $2}' | sort -u)"
  SC_NOT_IN_TABLE=""; SC_NOT_SHIPPED=""; SC_NO_SUITE=""
  while IFS='|' read -r h _c _s suite; do
    [ -n "$h" ] || continue
    if [ -z "$suite" ]; then SC_NO_SUITE="$SC_NO_SUITE $h(no suite named)"
    elif ! printf '%s\n' "$SC_SUITES" | grep -qxF "$suite"; then SC_NO_SUITE="$SC_NO_SUITE $h($suite)"; fi
  done <<SCEOF
$HOOK_TABLE
SCEOF
  for h in $SC_SHIPPED; do printf '%s\n' "$SC_TABLE"   | grep -qxF "$h" || SC_NOT_IN_TABLE="$SC_NOT_IN_TABLE $h"; done
  for h in $SC_TABLE;   do printf '%s\n' "$SC_SHIPPED" | grep -qxF "$h" || SC_NOT_SHIPPED="$SC_NOT_SHIPPED $h"; done
  if [ -z "$SC_NOT_IN_TABLE" ] && [ -z "$SC_NOT_SHIPPED" ] && [ -z "$SC_NO_SUITE" ]; then
    echo "TABLE_VS_BOOTSTRAP=ok($(printf '%s\n' "$SC_TABLE" | grep -c .) hooks, same set on both sides, every hook's suite is shipped)"; exit 0
  fi
  SC_WHY=""
  [ -z "$SC_NOT_IN_TABLE" ] || SC_WHY="shipped by $(basename "$BOOTSTRAP") but NOT in doctor's table (doctor would never check them):$SC_NOT_IN_TABLE"
  [ -z "$SC_NOT_SHIPPED" ]  || SC_WHY="${SC_WHY:+$SC_WHY; }in doctor's table but NOT shipped by $(basename "$BOOTSTRAP"):$SC_NOT_SHIPPED"
  [ -z "$SC_NO_SUITE" ]     || SC_WHY="${SC_WHY:+$SC_WHY; }hook whose suite is NOT shipped by $(basename "$BOOTSTRAP") (the hook would ship untested):$SC_NO_SUITE"
  echo "TABLE_VS_BOOTSTRAP=FAIL($SC_WHY)"; exit 1
fi

FAILS=0; WARNS=0; SKIPS=0; OKS=0
report() {  # report KEY STATE [detail]
  local key="$1" state="$2" detail="${3:-}"
  case "$state" in
    ok)      OKS=$((OKS+1)) ;;
    WARN)    WARNS=$((WARNS+1)) ;;
    FAIL)    FAILS=$((FAILS+1)) ;;
    SKIPPED) SKIPS=$((SKIPS+1)) ;;
  esac
  if [ -n "$detail" ]; then echo "$key=$state($detail)"; else echo "$key=$state"; fi
}

WORK="$(mktemp -d 2>/dev/null)" || { echo "doctor: cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

echo "# doctor: project=$PROJECT"
echo "# doctor: hooks-dir=$HOOKS_DIR"

# --- 1. interpreter ----------------------------------------------------------
# Same probe, same order, as the hooks themselves: a `command -v python3` hit is NOT
# enough (macOS ships a python3 shim that exists and cannot run until the developer
# tools are installed), so the candidate has to actually execute.
PY=""
for candidate in python3 python "py -3"; do
  if $candidate -c "import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
HAVE_PYTHON3=0
if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)" >/dev/null 2>&1; then HAVE_PYTHON3=1; fi
if [ -z "$PY" ]; then
  report PYTHON FAIL "no working interpreter among: python3, python, py -3 -- EVERY hook takes its fail-open branch and no gate fires"
else
  PY_WHERE="$(command -v ${PY%% *} 2>/dev/null)"; PY_VER="$($PY -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"
  if [ "$HAVE_PYTHON3" = 1 ]; then
    report PYTHON ok "hooks will use: $PY -> ${PY_WHERE:-?} $PY_VER"
  else
    report PYTHON WARN "hooks will use: $PY -> ${PY_WHERE:-?} $PY_VER, but \`python3\` itself does not run; hooks and suites that call python3 by name will fail open"
  fi
fi

# --- 2. git ------------------------------------------------------------------
HAVE_GIT=0
if ! command -v git >/dev/null 2>&1; then
  report GIT FAIL "git is not installed -- review-gate and gitleaks-gate read the staged index"
elif ! git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  report GIT FAIL "$PROJECT is not a git repository -- review-gate and gitleaks-gate read the staged index"
else
  HAVE_GIT=1; report GIT ok "$(git --version 2>/dev/null)"
fi

# --- 3. gitleaks -------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  GL_VER="$(gitleaks version 2>/dev/null | head -n 1)"
  if [ -n "$GL_VER" ]; then report GITLEAKS ok "$GL_VER"
  else report GITLEAKS WARN "gitleaks is on PATH but \`gitleaks version\` printed nothing -- gitleaks-gate.sh will warn and ALLOW on a tool error"; fi
else
  report GITLEAKS WARN "not installed -- gitleaks-gate.sh warns and ALLOWS every commit, so nothing scans staged secrets"
fi

# --- 4. registration (parsed once, consumed below) ---------------------------
# Emits one TSV row per expectation:  REG <hook> <yes|no> <detail>
# and one per registered .claude/hooks/ command:  CMD <basename>
REG_STATE="unknown"   # ok | nofile | badjson | nopython
REG_OUT="$WORK/reg.tsv"; : > "$REG_OUT"
if [ ! -f "$SETTINGS" ]; then
  REG_STATE="nofile"; report SETTINGS FAIL "not found: $SETTINGS -- no hook is registered, so none will ever run"
elif [ -z "$PY" ]; then
  REG_STATE="nopython"; report SETTINGS SKIPPED "no Python interpreter to parse $SETTINGS"
else
  HOOK_TABLE="$HOOK_TABLE" $PY - "$SETTINGS" "$SETTINGS_LOCAL" > "$REG_OUT" 2> "$WORK/reg.err" <<'PYEOF'
import json, os, sys

registered = []   # (event, matcher, command)
for fname in sys.argv[1:]:
    if not os.path.isfile(fname):
        continue
    with open(fname) as fh:
        data = json.load(fh)
    hooks = data.get("hooks") if isinstance(data, dict) else None
    if not isinstance(hooks, dict):
        continue
    for event, groups in hooks.items():
        for group in groups if isinstance(groups, list) else []:
            if not isinstance(group, dict):
                continue
            matcher = group.get("matcher", "") or ""
            for h in group.get("hooks", []) or []:
                if isinstance(h, dict) and h.get("type", "command") == "command":
                    registered.append((event, matcher, str(h.get("command", ""))))

def covers(matcher, tool):
    if matcher in ("", "*", ".*"):
        return True
    return tool in [p.strip() for p in matcher.split("|")]

for row in os.environ["HOOK_TABLE"].splitlines():
    if not row.strip():
        continue
    name, _cls, spec = row.split("|")[:3]
    missing = []
    for want in spec.split(","):
        event, _, tools = want.partition(":")
        mine = [(m, c) for (e, m, c) in registered if e == event and ("/" + name) in c]
        if not mine:
            missing.append(event)
            continue
        for tool in [t for t in tools.split("+") if t]:
            if not any(covers(m, tool) for (m, _c) in mine):
                missing.append("%s[%s]" % (event, tool))
    print("REG\t%s\t%s\t%s" % (name, "no" if missing else "yes", ",".join(missing)))

seen = set()
for _e, _m, command in registered:
    marker = ".claude/hooks/"
    at = command.find(marker)
    if at < 0:
        continue
    tail = command[at + len(marker):]
    base = tail.split()[0].strip("\"'") if tail.split() else ""
    if base and base not in seen:
        seen.add(base)
        print("CMD\t%s" % base)
PYEOF
  if [ $? -eq 0 ]; then
    REG_STATE="ok"; report SETTINGS ok "$SETTINGS"
  else
    REG_STATE="badjson"; report SETTINGS FAIL "could not parse $SETTINGS: $(tail -n 1 "$WORK/reg.err" 2>/dev/null)"
  fi
fi
reg_field() { awk -F'\t' -v n="$1" -v c="$2" '$1=="REG" && $2==n {print $c}' "$REG_OUT"; }

# --- 5. each hook: present + executable, then registered ----------------------
HOOKS_PRESENT=0
while IFS='|' read -r NAME CLASS SPEC _SUITE; do
  [ -n "$NAME" ] || continue
  KEY="${NAME%.sh}"; FILE="$HOOKS_DIR/$NAME"
  REGD=""; [ "$REG_STATE" = ok ] && REGD="$(reg_field "$NAME" 3)"
  if [ -f "$FILE" ]; then
    HOOKS_PRESENT=$((HOOKS_PRESENT+1))
    if [ -x "$FILE" ]; then report "HOOK_$KEY" ok
    else report "HOOK_$KEY" FAIL "present but NOT executable -- a hook that cannot launch never blocks (chmod +x $FILE)"; fi
  elif [ "$CLASS" = required ]; then
    report "HOOK_$KEY" FAIL "missing: $FILE"
  elif [ "$REG_STATE" != ok ]; then
    report "HOOK_$KEY" SKIPPED "optional hook not installed; whether it is registered could not be determined"
  elif [ "$REGD" = yes ] || grep -q "^CMD	$NAME\$" "$REG_OUT"; then
    report "HOOK_$KEY" FAIL "registered in settings but the file is missing: $FILE -- a hook that cannot launch never blocks"
  else
    report "HOOK_$KEY" SKIPPED "optional hook, not installed and not registered"
  fi

  case "$REG_STATE" in
    ok)
      if [ "$REGD" = yes ]; then report "REG_$KEY" ok
      elif [ ! -f "$FILE" ] && [ "$CLASS" = optional ]; then report "REG_$KEY" SKIPPED "optional hook, not installed"
      else report "REG_$KEY" FAIL "not registered for: $(reg_field "$NAME" 4) (expected $SPEC) -- an unregistered hook never runs"; fi ;;
    nofile)   report "REG_$KEY" SKIPPED "no settings file to read" ;;
    badjson)  report "REG_$KEY" SKIPPED "settings file did not parse" ;;
    *)        report "REG_$KEY" SKIPPED "no Python interpreter to parse settings" ;;
  esac
done <<EOF
$HOOK_TABLE
EOF

# Every registered .claude/hooks/ command -- including ones this script does not know --
# must point at a file that exists and can launch.
if [ "$REG_STATE" = ok ]; then
  DANGLING=""
  while IFS='	' read -r KIND BASE; do
    [ "$KIND" = CMD ] || continue
    if [ ! -f "$HOOKS_DIR/$BASE" ]; then DANGLING="$DANGLING $BASE(missing)"
    elif [ ! -x "$HOOKS_DIR/$BASE" ]; then DANGLING="$DANGLING $BASE(not-executable)"; fi
  done < "$REG_OUT"
  if [ -z "$DANGLING" ]; then report REGISTERED_FILES ok "every registered hook command resolves to an executable file"
  else report REGISTERED_FILES FAIL "registered but cannot launch:$DANGLING"; fi
else
  report REGISTERED_FILES SKIPPED "registration could not be read"
fi

# --- 6. the suites ------------------------------------------------------------
# Verdict comes from COUNTING the suites' own `PASS:` / `FAIL:` lines plus the exit code,
# never from a line position. Zero assertions is "could not run", not "passed".
kill_tree() {  # kill_tree SIGNAL PID -- the pid and, where `ps` can list them, its descendants
  local sig="$1" root="$2" kid
  if command -v ps >/dev/null 2>&1; then
    for kid in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$root" '$2==p{print $1}'); do kill_tree "$sig" "$kid"; done
  fi
  kill "-$sig" "$root" 2>/dev/null
}
# run_with_timeout SECONDS LOGFILE cmd...   -> the command's rc, or 124 when WE killed it.
# The timeout is detected from a flag file the watchdog writes BEFORE it kills, never from
# the exit status: a TERM'd child reports 143 (137 after KILL), and the first version of this
# function inferred "timed out" from whether the watchdog had already exited -- it never had,
# so a hung suite with no assertions read as "could not run" and doctor exited 0.
run_with_timeout() {
  local secs="$1" log="$2"; shift 2
  local flag="$WORK/timed-out.$RANDOM$RANDOM"; rm -f "$flag"
  "$@" > "$log" 2>&1 &
  local pid=$!
  ( sleep "$secs"; : > "$flag"; kill_tree TERM "$pid"; sleep 2; kill_tree KILL "$pid" ) >/dev/null 2>&1 &
  local wd=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill_tree TERM "$wd"; wait "$wd" 2>/dev/null
  if [ -f "$flag" ]; then rm -f "$flag"; return 124; fi
  return $rc
}

SUITES_FOUND=0
if [ "$RUN_SUITES" = 0 ]; then
  report SUITES SKIPPED "--no-suites"
elif [ ! -d "$HOOKS_DIR" ]; then
  report SUITES FAIL "hooks dir not found: $HOOKS_DIR"
else
  for SUITE in "$HOOKS_DIR"/test-*.sh; do
    [ -f "$SUITE" ] || continue
    SUITES_FOUND=$((SUITES_FOUND+1))
    SKEY="SUITE_$(basename "$SUITE" .sh)"
    if [ "$HAVE_PYTHON3" != 1 ]; then
      report "$SKEY" SKIPPED "could not run: the suites call \`python3\` by name and it does not run here"; continue
    fi
    if [ "$HAVE_GIT" != 1 ] && ! command -v git >/dev/null 2>&1; then
      report "$SKEY" SKIPPED "could not run: git is not installed"; continue
    fi
    if [ "$(basename "$SUITE")" = "test-telemetry-ingest.sh" ]; then
      # This one suite drives the Vibe Board package (Layer 2): cases 5-9 need node plus a
      # BUILT clone beside the hooks' project root. Absent that it cannot run -- say so.
      SROOT="$(cd "$HOOKS_DIR/../.." 2>/dev/null && pwd)"; PKG=""
      for d in vibe-board ve-vibe-board; do [ -f "$SROOT/$d/scripts/ingest-gate-events.mjs" ] && PKG="$SROOT/$d" && break; done
      if ! command -v node >/dev/null 2>&1; then
        report "$SKEY" SKIPPED "could not run: node is not installed (needed by the telemetry ingest script)"; continue
      elif [ -z "$PKG" ]; then
        report "$SKEY" SKIPPED "could not run: no vibe-board/ or ve-vibe-board/ clone in $SROOT (Layer 2 not installed)"; continue
      elif [ ! -f "$PKG/dist/tools/gate-events.js" ]; then
        report "$SKEY" SKIPPED "could not run: $PKG is not built (npm install && npm run build)"; continue
      fi
    fi
    LOG="$WORK/$(basename "$SUITE").log"
    # CLAUDE_PROJECT_DIR is unset so a suite run from inside a live session cannot append
    # test events to the real project's telemetry file.
    run_with_timeout "$SUITE_TIMEOUT" "$LOG" env -u CLAUDE_PROJECT_DIR bash "$SUITE"; RC=$?
    NPASS=$(grep -c '^PASS:' "$LOG"); NFAIL=$(grep -c '^FAIL:' "$LOG")
    case "x${NPASS}x${NFAIL}x" in
      xx*|*xx|*[!0-9x]*) report "$SKEY" FAIL "could not count the suite's PASS:/FAIL: lines (got '$NPASS'/'$NFAIL') -- NOT a verdict on the hook"; continue ;;
    esac
    if [ "$RC" = 124 ]; then
      report "$SKEY" FAIL "timed out after ${SUITE_TIMEOUT}s ($NPASS passed, $NFAIL failed before the kill)"
    elif [ "$NFAIL" -gt 0 ]; then
      report "$SKEY" FAIL "$NPASS passed, $NFAIL failed"
    elif [ "$RC" -gt 128 ]; then
      report "$SKEY" FAIL "killed by signal $((RC-128)) after $NPASS passed, 0 failed -- a suite that dies is not a suite that could not run"
    elif [ "$NPASS" -eq 0 ] && [ "$RC" != 0 ]; then
      report "$SKEY" FAIL "exited $RC without reaching a single assertion: $(tail -n 1 "$LOG" 2>/dev/null)"
    elif [ "$NPASS" -eq 0 ]; then
      # Exit 0 and nothing asserted: the suite declined to run (it says why on a SKIP: line).
      WHY="$(grep -m1 '^SKIP' "$LOG" 2>/dev/null)"; [ -n "$WHY" ] || WHY="exit 0 with no assertions and no SKIP: line"
      report "$SKEY" SKIPPED "could not run -- $WHY"
    elif [ "$RC" != 0 ]; then
      report "$SKEY" FAIL "$NPASS passed, 0 failed, but the suite exited $RC"
    else
      report "$SKEY" ok "$NPASS passed, 0 failed"
    fi
    if [ "$VERBOSE" = 1 ]; then sed 's/^/  | /' "$LOG"
    elif [ "$NFAIL" -gt 0 ]; then grep '^FAIL:' "$LOG" | sed 's/^/  | /'; fi
  done
  if [ "$SUITES_FOUND" = 0 ]; then
    report SUITES FAIL "no test-*.sh found in $HOOKS_DIR -- the gates here have never been shown to fire"
  else
    report SUITES ok "$SUITES_FOUND suite(s) found"
  fi
fi

# --- verdict -------------------------------------------------------------------
VERDICT=ok; EXIT=0
if [ "$FAILS" -gt 0 ]; then VERDICT=FAIL; EXIT=1
elif [ "$WARNS" -gt 0 ] || [ "$SKIPS" -gt 0 ]; then
  VERDICT=WARN; [ "$STRICT" = 1 ] && EXIT=1
fi
echo "DOCTOR=$VERDICT ok=$OKS fail=$FAILS warn=$WARNS skipped=$SKIPS strict=$STRICT"
exit $EXIT
