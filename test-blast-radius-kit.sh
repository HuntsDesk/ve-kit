#!/bin/bash
# test-blast-radius-kit.sh -- prove the kit's blast-radius engine works in a repo it
# has never seen. CI (.github/workflows/gates.yml) runs it on Ubuntu and macOS.
#
#   bash test-blast-radius-kit.sh [path/to/blast-radius.sh]   (default: beside this file)
#
# Everything runs in scratch git repos under one mktemp dir; nothing else is touched.
#   1. The engine's own --self-test passes against a minimal config.
#   2. blast-radius.conf.example parses as shipped, and with every example directive
#      switched on (its "#: " lines), so no documented syntax is wrong.
#   3. A CONFIGURED probe finds the case planted for it (importers, symbols, a
#      dual-access table, a flag, a one-way door, a trigger, a vendored copy), and a
#      never_read file stays invisible to every walker.
#   4. An UNCONFIGURED probe reports KEY=SKIPPED(not configured: <directive>), never an
#      empty value, and the run still exits 0.
#   5. An absent or invalid config fails closed: exit 2, one PROBE_FAILED=config line.
#   6. Mutation controls: without the planted flag the FLAGS assertion fails, and with
#      the engine's SKIPPED emitter removed the unconfigured assertions fail, so each
#      assertion depends on what it claims to test.
#
# Exit: 0 every test passed; 1 a test failed; 2 NOT EVALUATED (git, jq or ast-grep is
# missing, or the scratch repo could not be built). 2 is never a pass.
# Needs: git, jq, ast-grep (`sg` or `ast-grep`). ripgrep is optional (git grep fallback).
set -u
export LC_ALL=C

HERE=$(cd "$(dirname "$0")" && pwd -P)
ENGINE=${1:-$HERE/blast-radius.sh}
EXAMPLE=$HERE/blast-radius.conf.example
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
ne()  { echo "NOT EVALUATED: $1"; echo "---"; echo "$PASS passed, $FAIL failed (not evaluated)"; exit 2; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

[ -f "$ENGINE" ] || ne "engine not found: $ENGINE"
[ -f "$EXAMPLE" ] || ne "example config not found: $EXAMPLE"
for t in git jq; do command -v "$t" >/dev/null 2>&1 || ne "$t is not installed"; done
command -v sg >/dev/null 2>&1 || command -v ast-grep >/dev/null 2>&1 || ne "ast-grep is not installed (sg / ast-grep)"

S=$(mktemp -d "${TMPDIR:-/tmp}/test-blast-radius-kit.XXXXXX") || ne "mktemp"
S=$(cd "$S" && pwd -P)
trap 'rm -rf "$S"' EXIT
G() { git -c user.email=t@example.invalid -c user.name=t -c core.hooksPath=/dev/null "$@"; }

# new_repo <dir>: a git repo holding the engine at scripts/blast-radius.sh
new_repo() {
  mkdir -p "$1/scripts" "$1/.claude" && cp "$ENGINE" "$1/scripts/blast-radius.sh" \
    && (cd "$1" && git init -q .) >/dev/null 2>&1
}
# run <dir> <args...>: stdout in $OUT, rc in $RC
run() { local d=$1; shift; OUT=$(cd "$d" && /bin/bash scripts/blast-radius.sh "$@" 2>"$S/err"); RC=$?; }

# -- 1. the engine's own --self-test -----------------------------------------------
M=$S/minimal; new_repo "$M" || ne "scratch repo"
printf 'version 1\nend\n' > "$M/.claude/blast-radius.conf"
run "$M" --self-test
n=$(printf '%s\n' "$OUT" | grep -c '^SELFTEST_PASS')
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'SELFTEST=pass' && ! printf '%s\n' "$OUT" | grep -q '^SELFTEST_FAIL' && [ "$n" -ge 20 ]; then
  ok "engine --self-test passes against a minimal config (rc=0, $n cases)"
else bad "engine --self-test (rc=$RC, $n passing cases): $(printf '%s\n' "$OUT" | grep -m3 -E '^(SELFTEST_FAIL|PROBE_FAILED)')"; fi

# -- 2. the example config ----------------------------------------------------------
cp "$EXAMPLE" "$M/.claude/blast-radius.conf"
run "$M" --self-test
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'SELFTEST=pass' \
  && ok "blast-radius.conf.example parses as shipped (a valid, empty config)" \
  || bad "example as shipped (rc=$RC): $(printf '%s\n' "$OUT" | grep -m1 PROBE_FAILED)"
sed 's/^#: //' "$EXAMPLE" > "$M/.claude/blast-radius.conf"
nex=$(grep -c '^#: ' "$EXAMPLE")
run "$M" --self-test
if [ "$nex" -ge 30 ] && [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'SELFTEST=pass' && printf '%s\n' "$OUT" | grep -qx 'SELFTEST_NOTE probes configured: 8/8'; then
  ok "every example directive switched on ($nex lines) parses, and configures all 8 probes"
else bad "example with every directive on ($nex lines, rc=$RC): $(printf '%s\n' "$OUT" | grep -m1 -E 'PROBE_FAILED|SELFTEST_FAIL|probes configured')"; fi

# -- 3. a configured repo with planted cases -----------------------------------------
R=$S/repo; new_repo "$R" || ne "scratch repo"
mkdir -p "$R/src" "$R/lib" "$R/infra" "$R/zz-private" "$R/secret/area"
cat > "$R/src/a.ts" <<'EOF'
export function plantedSymbolAlpha() { return db.from('widgets').select('*'); }
export const flagged = useFlag('planted-flag');
EOF
printf "import { plantedSymbolAlpha } from './a';\nplantedSymbolAlpha();\n" > "$R/src/b.ts"
printf "export const reader = db.from('widgets').select('id');\n" > "$R/src/c.ts"
printf "import { thing } from './ctlmod';\nexport const ctlWordUse = thing;\n" > "$R/src/ctl.ts"
printf "export const thing = 1;\nexport const ctlWord = 2;\n" > "$R/src/ctlmod.ts"
printf 'import planted_mod\nQ = "SELECT id FROM widgets"\n' > "$R/lib/reader.py"
printf 'from ctlpy import x\n' > "$R/lib/ctl.py"
printf 'def planted_fn():\n    return 1\n' > "$R/planted_mod.py"
printf 'x: 1\n' > "$R/infra/x.yml"
for f in zz-private/leak secret/area/leak; do
  printf "import { plantedSymbolAlpha } from '../src/a';\nplantedSymbolAlpha();\nexport const r = db.from('widgets').select('*');\n" > "$R/$f.ts"
done
CONF_FULL='version 1
never_read secret/area
never_read_any zz-private
frontend_dirs src
importers_ts_control src/ctl.ts ctlmod
importers_py_control lib/ctl.py ctlpy
symbols_control src/ctlmod.ts ctlWord
tables_control \.from\(['"'"'"]widgets['"'"'"] widgets reader in src
one_way planted_door infra/*
trigger_env main TRIGGERS_MAIN always
trigger src/* main:deploy-web
trigger_control src/a.ts main:deploy-web
dual_access widgets
vendored src/a.ts|lib/a_copy.ts
flag_re useFlag\([[:space:]]*['"'"'"][a-z0-9_-]+
end'
printf '%s\n' "$CONF_FULL" > "$R/.claude/blast-radius.conf"
(cd "$R" && git add -A . && G commit -qm init --no-verify) >/dev/null 2>&1 || ne "scratch commit"
no_nr() { ! printf '%s\n' "$1" | grep -qiE 'zz-private|secret/area'; }

run "$R" --files src/a.ts
[ "$RC" = 0 ] && ok "configured run: rc=0" || bad "configured run rc=$RC: $(head -3 "$S/err")"
for want in "TRIGGERS_MAIN=deploy-web" "IMPORTERS=src/a.ts:1" "plantedSymbolAlpha(in-file):1" "widgets[DUAL](readers=2 fe=1 be=1)" \
            "DUAL_ACCESS=widgets" "FLAGS=planted-flag(changed)" "VENDORED=src/a.ts (canonical=src/a.ts,copies=1; guard: none configured)"; do
  has "$OUT" "$want" && ok "configured probe finds its planted case: $want" || bad "configured: missing '$want'"
done
has "$OUT" "UNCONTROLLED" && bad "configured run printed UNCONTROLLED (a search ran without its control)" || ok "configured run: every search has its positive control"
no_nr "$OUT" && ok "never_read files (a prefix and an any-depth name) are invisible to every walker" || bad "a never_read path appears in the output"
run "$R" --files infra/x.yml
has "$OUT" "ONE_WAY=planted_door" && ok "one_way glob fires (ONE_WAY=planted_door)" || bad "one_way planted_door missing"
run "$R" --files zz-private/leak.ts
has "$OUT" "NEVER_READ_REFUSED=1" && ! has "$OUT" "FILE=" && ok "--files on a never_read path is refused before any lookup" || bad "never_read input not refused"
run "$R" --brief --files src/a.ts
[ "$(printf '%s\n' "$OUT" | grep -c .)" -le 12 ] && has "$(printf '%s\n' "$OUT" | head -1)" "evaluated=8/8" \
  && ok "--brief (what the fact-gate hook appends) is <= 12 lines, header evaluated=8/8" || bad "--brief: $(printf '%s\n' "$OUT" | head -1)"

# Control: the FLAGS assertion depends on the planted flag, not on the fixture text.
printf 'export function plantedSymbolAlpha() { return db.from(%s).select(%s); }\n' "'widgets'" "'*'" > "$R/src/a.ts"
run "$R" --files src/a.ts
! has "$OUT" "planted-flag" && ok "control: with the planted flag removed, FLAGS no longer reports it" || bad "control: FLAGS still reports a flag that is not there"
(cd "$R" && git checkout -q -- src/a.ts)

# -- 4. unconfigured: SKIPPED, never empty --------------------------------------------
unconfigured() { # <engine> -> prints "<n of 6 SKIPPED lines> <empty-key count> <rc>"
  printf 'version 1\nend\n' > "$R/.claude/blast-radius.conf"
  OUT=$(cd "$R" && /bin/bash "$1" --files src/a.ts 2>/dev/null); RC=$?
  local n=0 e=0 k
  for k in "ONE_WAY=SKIPPED(not configured: one_way)" "TRIGGERS=SKIPPED(not configured: trigger)" "VENDORED=SKIPPED(not configured: vendored_registry)" \
           "DUAL_ACCESS=SKIPPED(not configured: dual_access_from)" "FLAGS=SKIPPED(not configured: flag_re)" "BANNED_PATTERNS=SKIPPED(not configured: banned_guard)"; do
    printf '%s\n' "$OUT" | grep -qxF "$k" && n=$((n+1))
  done
  for k in ONE_WAY TRIGGERS VENDORED DUAL_ACCESS FLAGS; do printf '%s\n' "$OUT" | grep -qx "$k=" && e=$((e+1)); done
  echo "$n $e $RC"
}
set -- $(unconfigured "$R/scripts/blast-radius.sh")
[ "$1" = 6 ] && ok "unconfigured: all 6 unconfigured probes say KEY=SKIPPED(not configured: <directive>)" || bad "unconfigured: only $1 of 6 SKIPPED lines"
[ "$2" = 0 ] && ok "unconfigured: no probe key is printed empty (empty would read as 'none')" || bad "unconfigured: $2 probe keys printed EMPTY"
[ "$3" = 0 ] && ok "unconfigured: the run still exits 0 (not configured is not a failure)" || bad "unconfigured: rc=$3"
run "$R" --files src/a.ts   # unconfigured() ran in a subshell; re-run for its output here
for k in "IMPORTERS=UNCONTROLLED(no importers_ts_control):" "SYMBOLS=UNCONTROLLED(no symbols_control):" "TABLES=UNCONTROLLED(no tables_control):"; do
  has "$OUT" "$k" && ok "unconfigured: a search with no control is labelled ${k%%=*}=UNCONTROLLED" || bad "unconfigured: missing '$k'"
done
# Mutation control: with the SKIPPED emitter removed the same assertions must fail.
MUT=$S/mutant-no-skipped.sh
sed 's/^skipped() { out "\$1=SKIPPED(not configured: \$2)"; }$/skipped() { :; }/' "$R/scripts/blast-radius.sh" > "$MUT"
if cmp -s "$R/scripts/blast-radius.sh" "$MUT"; then bad "mutation did not apply: the SKIPPED emitter"
else
  set -- $(unconfigured "$MUT")
  [ "$1" = 0 ] && ok "mutation caught: without the SKIPPED emitter the unconfigured assertions fail (0 of 6 SKIPPED lines)" \
    || bad "mutation NOT caught: $1 SKIPPED lines without the emitter"
fi

# -- 5. absent or invalid config fails closed ---------------------------------------
fc() { # <label> <expected reason>
  run "$R" --files src/a.ts
  if [ "$RC" = 2 ] && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && has "$OUT" "PROBE_FAILED=config (" && has "$OUT" "$2" && ! has "$OUT" "FILE="; then
    ok "fail closed: $1 -> rc=2, one PROBE_FAILED=config line ('$2')"
  else bad "fail closed: $1 (rc=$RC, got: $(printf '%s\n' "$OUT" | head -2 | tr '\n' ' '))"; fi
}
rm -f "$R/.claude/blast-radius.conf"; fc "absent config" "is absent"
printf 'version 1\nfrobnicate x\nend\n' > "$R/.claude/blast-radius.conf"; fc "unknown directive" "unknown directive 'frobnicate'"
printf 'version 1\nnever_read secret/area\n' > "$R/.claude/blast-radius.conf"; fc "no end line" "no 'end' line"
printf 'version 1\nflag_re useFlag(\nend\n' > "$R/.claude/blast-radius.conf"; fc "an ERE that does not compile" "bad ERE in flag_re"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
