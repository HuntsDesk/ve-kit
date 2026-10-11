#!/usr/bin/env bash
#
# blast-radius.sh — what could this change break, beyond its obvious callers?
#
# A generic engine. It gathers evidence in one deterministic, read-only pass:
# one-way doors, deploy triggers, vendored copies, importers (ast-grep),
# references to changed exported symbols, SQL tables and their readers, and
# feature-flag references. Every project-specific fact lives in the project
# config, .claude/blast-radius.conf (format below): which paths it must never
# read, the trigger map, the vendored-copy registry, the curated dual-access
# table list, flag patterns, positive controls and guard scripts. Nothing in
# this file names a project.
#
# The judgment step ("this is safe because <fact>", proven by running
# something) lives in the /blast-radius skill. This script only gathers
# evidence; it never claims a change is safe.
#
# USAGE
#   scripts/blast-radius.sh --staged            [--brief]
#   scripts/blast-radius.sh --range A..B        [--brief]
#   scripts/blast-radius.sh --files P [P ...]   [--brief]
#
#   --brief   at most 12 lines, for a hook's additionalContext
#   --self-test  prove the config parser and its fail-closed reasons, path
#             canonicalisation, and the never_read refusal on built-in and
#             derived strings (reads and lists nothing; exit 0 pass, 2 fail)
#   --guards  (full mode) also run the config's banned_guard script (repo-wide;
#             it does not depend on the change). The config's vendored_guard
#             runs in full mode whenever a registered copy changed.
#
# OUTPUT  KEY=value lines. Grep a key; never read a line by its position.
#         KEY=SKIPPED(not configured: <directive>) means the config does not
#         cover that probe: it was not run, which is NOT "none".
#         A value prefixed UNCONTROLLED(no <directive>): came from a search
#         with no positive control, so an empty or short result is unproven.
#
# EXIT    0  the run completed and every configured probe evaluated (a key may
#            still be empty: that is "found nothing", and the probe's control
#            passed)
#         2  a probe failed (PROBE_FAILED=<name> says which), usage is wrong,
#            or the config failed to load. A failed probe is NOT a claim that
#            nothing is affected.
#
# GUARANTEES  read-only: no network, no DB, no writes outside one mktemp dir
#             (removed on exit). bash 3.2 (macOS) safe; no GNU-only flags; no
#             config string is ever passed to eval; every config ERE is
#             compiled at load, and a grep error in a probe is a probe
#             failure. Paths listed under never_read are refused on their
#             lexical string, again on their physical parent, and (for a
#             symlink, inside or outside the repo) on the final target of the
#             chain, before anything reads them; and they are excluded from
#             every walker (git diff/ls-files/grep pathspecs, ripgrep --glob,
#             ast-grep --globs). Because walkers follow a symlinked root and
#             those excludes are anchored to real paths, a walker root that is,
#             or passes through, a symlink to a never_read path or to any
#             directory containing one is refused. A file is read from the
#             working tree only after its fully resolved real path passes. Residual: resolving
#             a physical parent is a chdir, so a symlinked PARENT that leads
#             into a never_read directory is entered (never listed or read)
#             before it is refused.
#
# KNOWN LIMIT  ast-grep skips a file it cannot read (e.g. mode 000) with
#             exit 0 and no message, so such a file is invisible to IMPORTERS
#             and nothing here can tell. Readable repos are assumed.
#
# THREAT MODEL  The engine trusts git's view of the repository: GIT_DIR,
#             GIT_WORK_TREE (or a .git file pointing elsewhere) decide which
#             tree the repo root, the config and every exclusion come from. It
#             does not defend against a hostile environment or a hostile config
#             author; the config is protected by review, not by this script.
#
# OVERRIDES (tests and mutation checks)
#   BLAST_SG_BIN   ast-grep binary, used as given (default: ast-grep, then an
#                  `sg` whose --version says ast-grep; on Debian/Ubuntu `sg`
#                  is shadow-utils' "execute as group" tool)
#   BLAST_SG_CANDIDATES  the names/paths tried when BLAST_SG_BIN is unset
#                  (tests: hide a machine-wide ast-grep)
#   BLAST_RG_BIN   ripgrep binary  (default: rg on PATH, then the ripgrep
#                  bundled in the Claude Code binary, then `git grep`)
#   BLAST_JQ_BIN   jq binary       (default: jq)
#
# ── CONFIG: .claude/blast-radius.conf ──────────────────────────────────────
# Fixed path, no override. It FAILS CLOSED: absent, unreadable, a symlink (or
# under a symlinked .claude/), no `version 1` first, no `end` last, content
# after `end`, an unknown directive, a duplicated single-value directive or a
# malformed value prints `PROBE_FAILED=config (<reason>)` and exits 2 before
# any path is resolved or read. The file is copied once into the temp dir and
# only that snapshot is parsed.
#
# One directive per line: `<directive> <args...>`. Blank lines and lines whose
# first non-blank character is `#` are ignored; CR line endings are stripped.
# <path> values are repo-relative and normalised (./, //, trailing /); globs,
# `..` and absolute paths are refused. <glob> values are bash `case` patterns
# (`*` crosses `/`). <ERE> and <text> values are the REST of the line.
#
#   version 1                          first directive
#   end                                last directive (a truncated file fails)
#
#   never_read <path>                  refuse this path and everything under it
#   never_read_any <name>              refuse a directory of this name at any
#                                      depth. Both are case-insensitive. The
#                                      engine derives the variants it tests
#                                      (case, ./, a/../, //, trailing slash,
#                                      bare dir); --self-test runs them all.
#   never_read_report <KEY> <noun>     key + noun used when a path is refused
#                                      (default NEVER_READ_REFUSED / never_read)
#   selftest_canon <input> <want>      extra --self-test case. <want> is a
#                                      repo-relative path, REFUSE or
#                                      OUTSIDE:<abs>; `<repo>` in <input> is
#                                      the repo root. Every REFUSE line is
#                                      re-checked on EVERY run.
#
#   code_dirs <path>...                where text searches run (default: .)
#   frontend_dirs <path>...            one importer scope; fe= reader counts
#   scope_root <path>...               <root>/<x>/... is its own importer scope
#                                      (one build context per <x>)
#   importers_py_shared <path> <path>... a shared python dir, and the dirs
#                                      searched for its importers
#   ts_alias <prefix> <replacement>    a TS import alias (spec prefix -> dir/)
#   importers_ts_control <file> <stem> [<label>]   positive control: <file>
#                                      imports a module named <stem>
#   importers_py_control <file> <module> [<label>]
#   symbols_control <file> <word>      positive control: the symbol search
#                                      finds <word> in <file>
#   tables_control <ERE> <label>       positive control: the reader search
#                                      finds <ERE> under code_dirs
#
#   one_way <label> <glob>...          a changed path matching any <glob> is a
#                                      one-way door <label> (every matching
#                                      line fires; labels are a sorted set)
#   one_way_content <label> <glob> <ERE>   same, when a changed line of a path
#                                      matching <glob> matches <ERE> (-i)
#
#   trigger_env <env> <KEY> <always|nonempty>  an output key per environment
#   trigger <glob> [<env>:<name>...]   FIRST MATCH WINS, in file order. A line
#                                      with no outputs matches, emits nothing
#                                      and stops (an explicit "fires nothing")
#   trigger_svc <prefix> <svc,svc,...> <env>:<name>...  matches
#                                      <prefix><svc>/... for a listed <svc>;
#                                      `<svc>` in a name is replaced. Takes
#                                      part in the same first-match order.
#   trigger_always <env> <name>        appended as <name>(always)
#   trigger_control <path> <env>:<name>   positive control: <path> must
#                                      classify to include this output
#   trigger_note <ERE> <text>          note when a changed path matches
#                                      (only when the trigger map evaluated)
#   note <ERE> <text>                  note when a changed path matches
#
#   vendored_registry <file>           lines `"canonical|copy|copy"` in <file>
#   vendored <canonical>|<copy>...     an inline registry entry
#   vendored_guard <file>              run (full mode) when a copy changed
#   dual_access_from <file> <min> <anchor text>   the line after <anchor> lists
#                                      `table` names; fewer than <min> fails
#   dual_access <table>...             an inline dual-access list
#   flag_re <ERE>                      a flag reference; the last quoted token
#                                      of a match is the flag name
#   flag_const_re <ERE>                a flag named through a constant
#   banned_guard <file>                run with --guards (needs ripgrep)
#   fact_gate_blast_re <regex>         read by the fact-gate hook, not here
#
# Every <file>/<path> a directive names goes through the same canonicalise-
# then-refuse step as a --files input before it is read, scanned or run.

set -o pipefail

ORIG_PWD=$PWD
SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/$(basename "$0")
REPO=$(git rev-parse --show-toplevel) || { echo "PROBE_FAILED=git_toplevel"; exit 2; }
cd "$REPO" || { echo "PROBE_FAILED=cd_repo"; exit 2; }

T=$(mktemp -d "${TMPDIR:-/tmp}/blast-radius.XXXXXX") || { echo "PROBE_FAILED=mktemp"; exit 2; }
trap 'rm -rf "$T"' EXIT
: >"$T/failed"; : >"$T/out"; : >"$T/notes"; : >"$T/synth"

usage() {
  sed -n '/^# USAGE/,/^# OUTPUT/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'
}
fail() { echo "PROBE_FAILED=$1${2:+ ($2)}" >>"$T/failed"; }
out()  { echo "$*" >>"$T/out"; }
note() { echo "$*" >>"$T/notes"; }
csv()  { sort -u | grep -v '^$' | paste -sd, - ; }
lower() { tr '[:upper:]' '[:lower:]'; }
skipped() { out "$1=SKIPPED(not configured: $2)"; }
LREPO=$(printf '%s' "$REPO" | lower)

# ── args ────────────────────────────────────────────────────────────────────
MODE=""; BRIEF=0; GUARDS=0; RANGE=""; : >"$T/files.in"
while [ $# -gt 0 ]; do
  case $1 in
    --files)  MODE=files; shift
              while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do echo "$1" >>"$T/files.in"; shift; done ;;
    --staged) MODE=staged; shift ;;
    --range)  MODE=range; RANGE=${2:-}; shift; [ $# -gt 0 ] && shift ;;
    --brief)  BRIEF=1; shift ;;
    --guards) GUARDS=1; shift ;;
    --self-test) MODE=selftest; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; echo "PROBE_FAILED=usage"; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { usage >&2; echo "PROBE_FAILED=usage (need --files, --staged or --range)"; exit 2; }
if [ "$MODE" = files ] && [ ! -s "$T/files.in" ]; then echo "PROBE_FAILED=usage (--files given no paths)"; exit 2; fi

# ── config parser ───────────────────────────────────────────────────────────
CONF_REL=.claude/blast-radius.conf
CONF_VERSION=1
LOWERS=abcdefghijklmnopqrstuvwxyz; UPPERS=ABCDEFGHIJKLMNOPQRSTUVWXYZ

cfg_reset() {
  CFG_ERR=""; CFG_VERSION=""; CFG_END=0; CFG_SEEN=" "; CFG_LINE=0
  NR_PREFIX=(); NR_ANY=(); NR_KEY=NEVER_READ_REFUSED; NR_NOUN=never_read
  ST_IN=(); ST_WANT=()
  CODE_DIRS_CFG=(); FE_DIRS=(); SCOPE_ROOTS=(); PY_SHARED=""; PY_SHARED_PATHS=()
  TS_ALIAS_P=(); TS_ALIAS_R=()
  TS_CTL_FILE=""; TS_CTL_STEM=""; TS_CTL_LABEL=""
  PY_CTL_FILE=""; PY_CTL_MOD=""; PY_CTL_LABEL=""
  SYM_CTL_FILE=""; SYM_CTL_WORD=""; TAB_CTL_RE=""; TAB_CTL_LABEL=""
  OW_LABEL=(); OW_GLOB=(); OWC_LABEL=(); OWC_GLOB=(); OWC_RE=()
  TR_KIND=(); TR_GLOB=(); TR_SVCS=(); TR_OUT=()
  TE_ENV=(); TE_KEY=(); TE_MODE=(); TA_ENV=(); TA_NAME=(); TC_PATH=(); TC_WANT=()
  TN_RE=(); TN_TEXT=(); NOTE_RE=(); NOTE_TEXT=()
  VEND_REG=""; VEND_INLINE=(); VEND_GUARD=""
  DUAL_FROM=""; DUAL_MIN=""; DUAL_ANCHOR=""; DUAL_INLINE=()
  FLAG_RE=""; FLAG_CONST_RE=""; BANNED_GUARD=""; FG_BLAST_RE=""
}
cfg_err() { [ -n "$CFG_ERR" ] || CFG_ERR="$1 (line $CFG_LINE)"; }
# cfg_once <directive>: a single-value directive may appear once.
cfg_once() {
  case $CFG_SEEN in *" $1 "*) cfg_err "duplicate $1"; return 1 ;; esac
  CFG_SEEN="$CFG_SEEN$1 "
}
# cfg_path <value> <directive>: a plain repo-relative path, normalised into REPLY.
cfg_path() {
  local v=$1
  case $v in ''|/*|*'*'*|*'?'*|*'['*|*'\'*) cfg_err "$2: '$1' must be a plain repo-relative path (no glob, not absolute)"; return 1 ;; esac
  case /$v/ in */../*) cfg_err "$2: '$1' must not contain '..'"; return 1 ;; esac
  while :; do
    case $v in
      ./*) v=${v#./} ;;
      *//*) v=${v%%//*}/${v#*//} ;;
      */./*) v=${v%%/./*}/${v#*/./} ;;
      */.) v=${v%/.} ;;
      */) v=${v%/} ;;
      *) break ;;
    esac
  done
  case $v in ''|.) cfg_err "$2: '$1' names the repo root"; return 1 ;; esac
  REPLY=$v
}
# cfg_word <value> <directive> <what>: a one-word value that may hold no glob character.
cfg_word() {
  case $1 in ''|*'*'*|*'?'*|*'['*) cfg_err "$2: '$1' is not a valid $3"; return 1 ;; esac
}
# rest_after <n> <rest>: REPLY = <rest> without its first n words.
rest_after() {
  local r=$2 i=0
  while [ $i -lt "$1" ]; do
    r=${r#"${r%%[![:space:]]*}"}; r=${r#"${r%%[[:space:]]*}"}; i=$((i+1))
  done
  REPLY=${r#"${r%%[![:space:]]*}"}
}

parse_config() { # $1 file. Returns 1 with CFG_ERR set on any failure.
  cfg_reset
  local line d rest n tok e
  local -a w
  while IFS= read -r line || [ -n "$line" ]; do
    CFG_LINE=$((CFG_LINE+1))
    line=${line%$'\r'}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    case $line in ''|'#'*) continue ;; esac
    if [ "$CFG_END" = 1 ]; then cfg_err "content after end"; break; fi
    d=${line%%[[:space:]]*}
    rest=${line#"$d"}; rest=${rest#"${rest%%[![:space:]]*}"}
    # Split on blanks with pathname expansion off: values hold globs.
    set -f; w=($rest); set +f
    n=${#w[@]}
    if [ -z "$CFG_VERSION" ] && [ "$d" != version ]; then cfg_err "first directive must be 'version $CONF_VERSION', got '$d'"; break; fi
    case $d in
      version) cfg_once version || break
        [ "$rest" = "$CONF_VERSION" ] || { cfg_err "bad version '$rest' (this engine reads version $CONF_VERSION)"; break; }
        CFG_VERSION=$rest ;;
      end) [ -z "$rest" ] || { cfg_err "end takes no arguments"; break; }; CFG_END=1 ;;
      never_read)
        [ "$n" = 1 ] || { cfg_err "never_read takes one path"; break; }
        cfg_path "${w[0]}" never_read || break; NR_PREFIX+=("$REPLY") ;;
      never_read_any)
        [ "$n" = 1 ] || { cfg_err "never_read_any takes one name"; break; }
        case ${w[0]} in */*|.|..) cfg_err "never_read_any: '${w[0]}' must be one path segment"; break ;; esac
        cfg_path "${w[0]}" never_read_any || break; NR_ANY+=("$REPLY") ;;
      never_read_report) cfg_once "$d" || break
        [ "$n" -ge 2 ] || { cfg_err "never_read_report takes <KEY> <noun>"; break; }
        case ${w[0]} in [A-Z]*) ;; *) cfg_err "never_read_report: bad key '${w[0]}'"; break ;; esac
        case ${w[0]} in *[!A-Z0-9_]*) cfg_err "never_read_report: bad key '${w[0]}'"; break ;; esac
        NR_KEY=${w[0]}; rest_after 1 "$rest"; NR_NOUN=$REPLY ;;
      selftest_canon)
        [ "$n" = 2 ] || { cfg_err "selftest_canon takes <input> <want>"; break; }
        ST_IN+=("${w[0]}"); ST_WANT+=("${w[1]}") ;;
      code_dirs|frontend_dirs|scope_root)
        [ "$n" -ge 1 ] || { cfg_err "$d takes at least one path"; break; }
        for tok in "${w[@]}"; do
          cfg_path "$tok" "$d" || break
          case $d in code_dirs) CODE_DIRS_CFG+=("$REPLY") ;; frontend_dirs) FE_DIRS+=("$REPLY") ;; *) SCOPE_ROOTS+=("$REPLY") ;; esac
        done ;;
      importers_py_shared) cfg_once "$d" || break
        [ "$n" -ge 2 ] || { cfg_err "importers_py_shared takes <dir> <search path>..."; break; }
        cfg_path "${w[0]}" "$d" || break; PY_SHARED=$REPLY
        for tok in "${w[@]:1}"; do cfg_path "$tok" "$d" || break; PY_SHARED_PATHS+=("$REPLY"); done ;;
      ts_alias)
        [ "$n" = 2 ] || { cfg_err "ts_alias takes <prefix> <replacement>"; break; }
        cfg_word "${w[0]}" "$d" prefix || break; cfg_word "${w[1]}" "$d" replacement || break
        TS_ALIAS_P+=("${w[0]}"); TS_ALIAS_R+=("${w[1]}") ;;
      importers_ts_control|importers_py_control) cfg_once "$d" || break
        [ "$n" -ge 2 ] || { cfg_err "$d takes <file> <module> [<label>]"; break; }
        cfg_path "${w[0]}" "$d" || break; e=$REPLY
        case ${w[1]} in ''|*[!A-Za-z0-9_.-]*) cfg_err "$d: bad module name '${w[1]}'"; break ;; esac
        rest_after 2 "$rest"
        if [ "$d" = importers_ts_control ]; then TS_CTL_FILE=$e; TS_CTL_STEM=${w[1]}; TS_CTL_LABEL=${REPLY:-${e##*/} imports ${w[1]}}
        else PY_CTL_FILE=$e; PY_CTL_MOD=${w[1]}; PY_CTL_LABEL=${REPLY:-$e imports ${w[1]}}; fi ;;
      symbols_control) cfg_once "$d" || break
        [ "$n" = 2 ] || { cfg_err "symbols_control takes <file> <word>"; break; }
        cfg_path "${w[0]}" "$d" || break; SYM_CTL_FILE=$REPLY
        case ${w[1]} in ''|*[!A-Za-z0-9_]*) cfg_err "symbols_control: bad word '${w[1]}'"; break ;; esac
        SYM_CTL_WORD=${w[1]} ;;
      tables_control) cfg_once "$d" || break
        [ "$n" -ge 2 ] || { cfg_err "tables_control takes <ERE> <label>"; break; }
        TAB_CTL_RE=${w[0]}; rest_after 1 "$rest"; TAB_CTL_LABEL=$REPLY ;;
      one_way)
        [ "$n" -ge 2 ] || { cfg_err "one_way takes <label> <glob>..."; break; }
        case ${w[0]} in *[!a-z0-9_]*) cfg_err "one_way: bad label '${w[0]}'"; break ;; esac
        for tok in "${w[@]:1}"; do OW_LABEL+=("${w[0]}"); OW_GLOB+=("$tok"); done ;;
      one_way_content)
        [ "$n" -ge 3 ] || { cfg_err "one_way_content takes <label> <glob> <ERE>"; break; }
        case ${w[0]} in *[!a-z0-9_]*) cfg_err "one_way_content: bad label '${w[0]}'"; break ;; esac
        rest_after 2 "$rest"; OWC_LABEL+=("${w[0]}"); OWC_GLOB+=("${w[1]}"); OWC_RE+=("$REPLY") ;;
      trigger|trigger_svc)
        if [ "$d" = trigger ]; then
          [ "$n" -ge 1 ] || { cfg_err "trigger takes <glob> [<env>:<name>...]"; break; }
          TR_KIND+=(glob); TR_GLOB+=("${w[0]}"); TR_SVCS+=(""); e=("${w[@]:1}")
        else
          [ "$n" -ge 3 ] || { cfg_err "trigger_svc takes <prefix> <svc,svc,...> <env>:<name>..."; break; }
          case ${w[1]} in *[!A-Za-z0-9_,.-]*) cfg_err "trigger_svc: bad service list '${w[1]}'"; break ;; esac
          TR_KIND+=(svc); TR_GLOB+=("${w[0]}"); TR_SVCS+=(",${w[1]},"); e=("${w[@]:2}")
        fi
        for tok in "${e[@]}"; do
          case $tok in *:?*) ;; *) cfg_err "$d: output '$tok' is not <env>:<name>"; break ;; esac
          cfg_word "$tok" "$d" output || break
        done
        TR_OUT+=("${e[*]}") ;;
      trigger_env)
        [ "$n" = 3 ] || { cfg_err "trigger_env takes <env> <KEY> <always|nonempty>"; break; }
        case ${w[2]} in always|nonempty) ;; *) cfg_err "trigger_env: mode must be always or nonempty"; break ;; esac
        case ${w[0]} in ''|*[!A-Za-z0-9_-]*) cfg_err "trigger_env: bad env '${w[0]}'"; break ;; esac
        case ${w[1]} in [A-Z]*) ;; *) cfg_err "trigger_env: bad key '${w[1]}'"; break ;; esac
        case ${w[1]} in *[!A-Z0-9_]*) cfg_err "trigger_env: bad key '${w[1]}'"; break ;; esac
        case " ${TE_ENV[*]} " in *" ${w[0]} "*) cfg_err "duplicate trigger_env ${w[0]}"; break ;; esac
        TE_ENV+=("${w[0]}"); TE_KEY+=("${w[1]}"); TE_MODE+=("${w[2]}") ;;
      trigger_always)
        [ "$n" = 2 ] || { cfg_err "trigger_always takes <env> <name>"; break; }
        TA_ENV+=("${w[0]}"); TA_NAME+=("${w[1]}") ;;
      trigger_control)
        [ "$n" = 2 ] || { cfg_err "trigger_control takes <path> <env>:<name>"; break; }
        case ${w[1]} in *:?*) ;; *) cfg_err "trigger_control: '${w[1]}' is not <env>:<name>"; break ;; esac
        TC_PATH+=("${w[0]}"); TC_WANT+=("${w[1]%%:*} ${w[1]#*:}") ;;
      trigger_note|note)
        [ "$n" -ge 2 ] || { cfg_err "$d takes <ERE> <text>"; break; }
        rest_after 1 "$rest"
        if [ "$d" = note ]; then NOTE_RE+=("${w[0]}"); NOTE_TEXT+=("$REPLY"); else TN_RE+=("${w[0]}"); TN_TEXT+=("$REPLY"); fi ;;
      vendored_registry|vendored_guard|banned_guard) cfg_once "$d" || break
        [ "$n" = 1 ] || { cfg_err "$d takes one file"; break; }
        cfg_path "${w[0]}" "$d" || break
        case $d in vendored_registry) VEND_REG=$REPLY ;; vendored_guard) VEND_GUARD=$REPLY ;; *) BANNED_GUARD=$REPLY ;; esac ;;
      vendored)
        [ "$n" = 1 ] || { cfg_err "vendored takes one canonical|copy|... entry"; break; }
        case ${w[0]} in *'|'?*) ;; *) cfg_err "vendored: '${w[0]}' needs canonical|copy"; break ;; esac
        VEND_INLINE+=("${w[0]}") ;;
      dual_access_from) cfg_once "$d" || break
        [ "$n" -ge 3 ] || { cfg_err "dual_access_from takes <file> <min> <anchor text>"; break; }
        cfg_path "${w[0]}" "$d" || break; DUAL_FROM=$REPLY
        case ${w[1]} in ''|*[!0-9]*) cfg_err "dual_access_from: <min> must be a number"; break ;; esac
        DUAL_MIN=${w[1]}; rest_after 2 "$rest"; DUAL_ANCHOR=$REPLY ;;
      dual_access)
        [ "$n" -ge 1 ] || { cfg_err "dual_access takes at least one table"; break; }
        DUAL_INLINE+=("${w[@]}") ;;
      flag_re|flag_const_re|fact_gate_blast_re) cfg_once "$d" || break
        [ -n "$rest" ] || { cfg_err "$d takes a regex"; break; }
        case $d in flag_re) FLAG_RE=$rest ;; flag_const_re) FLAG_CONST_RE=$rest ;; *) FG_BLAST_RE=$rest ;; esac ;;
      *) cfg_err "unknown directive '$d'"; break ;;
    esac
    [ -z "$CFG_ERR" ] || break
  done <"$1"
  [ -z "$CFG_ERR" ] || return 1
  CFG_LINE=end
  [ -n "$CFG_VERSION" ] || { cfg_err "no 'version $CONF_VERSION' line"; return 1; }
  [ "$CFG_END" = 1 ] || { cfg_err "no 'end' line: a truncated config is refused"; return 1; }
  # Lowercase and dedupe the never_read set (matching is case-insensitive).
  local x lowered
  if [ ${#NR_PREFIX[@]} -gt 0 ]; then
    lowered=$(printf '%s\n' "${NR_PREFIX[@]}" | lower | awk '!s[$0]++'); NR_PREFIX=()
    while IFS= read -r x; do NR_PREFIX+=("$x"); done <<<"$lowered"
  fi
  if [ ${#NR_ANY[@]} -gt 0 ]; then
    lowered=$(printf '%s\n' "${NR_ANY[@]}" | lower | awk '!s[$0]++'); NR_ANY=()
    while IFS= read -r x; do NR_ANY+=("$x"); done <<<"$lowered"
  fi
  # Every env a trigger names must have a trigger_env (output tokens hold no
  # glob character, so the unquoted split below is safe).
  local envs=" ${TE_ENV[*]} " envlist=""
  for x in "${TR_OUT[@]}"; do for tok in $x; do envlist="$envlist ${tok%%:*}"; done; done
  for x in "${TA_ENV[@]}" "${TC_WANT[@]%% *}"; do envlist="$envlist $x"; done
  for e in $envlist; do
    case $envs in *" $e "*) ;; *) cfg_err "env '$e' has no trigger_env line"; return 1 ;; esac
  done
  # A configured path may not itself be never_read (validated paths hold no
  # whitespace or glob character).
  if [ ${#NR_PREFIX[@]} -gt 0 ] || [ ${#NR_ANY[@]} -gt 0 ]; then
    lowered=$(printf '%s\n' "${CODE_DIRS_CFG[@]}" "${FE_DIRS[@]}" "${SCOPE_ROOTS[@]}" "${PY_SHARED_PATHS[@]}" \
      $PY_SHARED $TS_CTL_FILE $PY_CTL_FILE $SYM_CTL_FILE $VEND_REG $VEND_GUARD $BANNED_GUARD $DUAL_FROM | lower)
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      never_read_hit "$x" && { cfg_err "'$x' is a configured path inside never_read"; return 1; }
    done <<<"$lowered"
  fi
  # Every ERE a directive carries must compile: grep reads a bad pattern as
  # "no match" only by exiting 2, which a probe would otherwise report as
  # "none". One grep for all of them; on failure, find the culprit.
  local -a res=() resd=() eargs=()
  local k=0
  while [ $k -lt ${#OWC_RE[@]} ]; do res+=("${OWC_RE[$k]}"); resd+=(one_way_content); k=$((k+1)); done
  k=0; while [ $k -lt ${#TN_RE[@]} ]; do res+=("${TN_RE[$k]}"); resd+=(trigger_note); k=$((k+1)); done
  k=0; while [ $k -lt ${#NOTE_RE[@]} ]; do res+=("${NOTE_RE[$k]}"); resd+=(note); k=$((k+1)); done
  [ -n "$FLAG_RE" ] && { res+=("$FLAG_RE"); resd+=(flag_re); }
  [ -n "$FLAG_CONST_RE" ] && { res+=("$FLAG_CONST_RE"); resd+=(flag_const_re); }
  [ -n "$TAB_CTL_RE" ] && { res+=("$TAB_CTL_RE"); resd+=(tables_control); }
  if [ ${#res[@]} -gt 0 ]; then
    for x in "${res[@]}"; do eargs+=(-e "$x"); done
    grep -E "${eargs[@]}" </dev/null >/dev/null 2>&1
    if [ $? -gt 1 ]; then
      k=0
      while [ $k -lt ${#res[@]} ]; do
        grep -E -e "${res[$k]}" </dev/null >/dev/null 2>&1
        [ $? -le 1 ] || { cfg_err "bad ERE in ${resd[$k]}: ${res[$k]}"; return 1; }
        k=$((k+1))
      done
      cfg_err "the EREs do not compile together"; return 1
    fi
  fi
  return 0
}

# never_read_hit <lowercase repo-relative path>: 0 if refused. Pure string.
never_read_hit() {
  local p=$1 v
  for v in "${NR_PREFIX[@]}"; do case $p/ in "$v"/*) return 0 ;; esac; done
  never_read_hit_any "$p"
}
# never_read_hit_any <lowercase path, relative or absolute>: a never_read_any segment.
never_read_hit_any() {
  local p=$1 v
  for v in "${NR_ANY[@]}"; do case /$p/ in */"$v"/*) return 0 ;; esac; done
  return 1
}
# nr_abs_hit <lowercase absolute path>: refused when it is under the repo and
# never_read there, or carries a never_read_any segment anywhere (inside or
# outside the repo). Pure string.
nr_abs_hit() {
  case $1 in "$LREPO"/*) never_read_hit "${1:$((${#LREPO}+1))}" && return 0 ;; esac
  never_read_hit_any "$1"
}
# resolve_leaf <absolute path>: "OK:<physical path>" for the end of a symlink
# chain, "REFUSED:" when a hop's target is never_read, or "UNRESOLVED:" when
# the chain does not end within 8 hops (a loop). Each hop's target is refused
# on its LEXICAL string before anything (cd, lstat) touches it, then again on
# its physical parent. Reads link text only.
resolve_leaf() {
  local p=$1 t d i=0
  while [ -L "$p" ] && [ $i -lt 8 ]; do
    t=$(readlink "$p") || { echo "UNRESOLVED:"; return; }
    case $t in /*) p=$t ;; *) p=$(dirname "$p")/$t ;; esac
    p=$(printf '%s\n' "$p" | lexnorm)
    nr_abs_hit "$(printf '%s' "$p" | lower)" && { echo "REFUSED:"; return; }
    d=$(dirname "$p")
    if [ -d "$d" ]; then d=$(cd "$d" 2>/dev/null && pwd -P) && p=${d%/}/$(basename "$p"); fi
    nr_abs_hit "$(printf '%s' "$p" | lower)" && { echo "REFUSED:"; return; }
    i=$((i+1))
  done
  [ -L "$p" ] && { echo "UNRESOLVED:"; return; }
  echo "OK:$p"
}
# has_link <relative path>: 0 when any component of it is a symlink. Builtins
# only, and no word splitting, so a glob character in a path is inert.
has_link() {
  local rest=$1 acc="" c
  while [ -n "$rest" ]; do
    c=${rest%%/*}; acc=${acc:+$acc/}$c
    [ -L "$acc" ] && return 0
    [ "$c" = "$rest" ] && break
    rest=${rest#*/}
  done
  return 1
}
# nr_ancestor <lowercase repo-relative dir, "" for the root>: 0 when it is, or
# contains, a never_read prefix. A walker rooted at a symlink to such a dir
# reaches the prefix under an alias that the anchored excludes do not match.
nr_ancestor() {
  local v
  for v in "${NR_PREFIX[@]}"; do
    [ -z "$1" ] && return 0
    case $v/ in "$1"/*) return 0 ;; esac
  done
  return 1
}
# real_ok <path>: 0 when the fully resolved real path (physical parent, then
# the final target of a symlinked leaf) passes the refusal AND lies inside the
# physical repo root; 1 when it is never_read or does not resolve; 2 when it
# lies outside the repo (a protected tree may live outside it, and a symlink can
# point there). Every file this script reads from the working tree, and every
# symlinked file handed to a walker, goes through here first.
real_ok() {
  local abs d
  case $1 in /*) abs=$1 ;; *) abs=$REPO/$1 ;; esac
  abs=$(printf '%s\n' "$abs" | lexnorm)
  nr_abs_hit "$(printf '%s' "$abs" | lower)" && return 1
  d=$(dirname "$abs")
  if [ -d "$d" ]; then d=$(cd "$d" 2>/dev/null && pwd -P) && abs=${d%/}/$(basename "$abs"); fi
  nr_abs_hit "$(printf '%s' "$abs" | lower)" && return 1
  if [ -L "$abs" ]; then
    abs=$(resolve_leaf "$abs")
    case $abs in OK:*) abs=${abs#OK:} ;; *) return 1 ;; esac
    nr_abs_hit "$(printf '%s' "$abs" | lower)" && return 1
  fi
  case $abs/ in "$REPO"/*) return 0 ;; esac  # inside the repo, physically
  return 2  # outside the repo
}

# icase_glob <lowercase value>: [aA]-style glob (for case-sensitive walkers).
icase_glob() {
  local s=$1 o="" ch i k
  for ((i=0; i<${#s}; i++)); do
    ch=${s:i:1}
    case $ch in
      [a-z]) k=${LOWERS%%"$ch"*}; o="$o[$ch${UPPERS:${#k}:1}]" ;;
      *) o=$o$ch ;;
    esac
  done
  REPLY=$o
}

# build_excludes: the never_read set as git pathspecs, ripgrep and ast-grep globs.
build_excludes() {
  local v
  NR_GIT_EXCL=(); RG_EXCL=(); SG_EXCL=()
  for v in "${NR_PREFIX[@]}"; do
    NR_GIT_EXCL+=(":(exclude,icase,literal)$v")
    icase_glob "$v"
    RG_EXCL+=(--glob "!$REPLY" --glob "!$REPLY/**"); SG_EXCL+=(--globs "!$REPLY" --globs "!$REPLY/**")
  done
  for v in "${NR_ANY[@]}"; do
    NR_GIT_EXCL+=(":(exclude,icase,literal)$v" ":(exclude,icase,glob)**/$v" ":(exclude,icase,glob)**/$v/**")
    icase_glob "$v"
    RG_EXCL+=(--glob "!**/$REPLY" --glob "!**/$REPLY/**"); SG_EXCL+=(--globs "!**/$REPLY" --globs "!**/$REPLY/**")
  done
}

# canon_path <input>: the repo-relative path git uses for this file,
# "OUTSIDE_REPO:<absolute>", or "NEVER_READ:". Every --files input and every
# path the config names goes through here BEFORE any check, so `./x`, `a/../x`,
# `//`, a case variant (macOS is case-insensitive) and a symlinked parent all
# reach the same canonical string, and the never_read refusal is decided on
# that string before any lookup.
lexnorm() { awk -F/ '{n=0; for(i=1;i<=NF;i++){ if($i=="."||$i=="") continue; if($i==".."){ if(n>0) n--; continue }; a[++n]=$i }; o=""; for(i=1;i<=n;i++) o=o"/"a[i]; print (o==""?"/":o)}'; }
canon_path() {
  local p=$1 abs d b rel hit labs part cur c m tgt
  case $p in /*) abs=$p ;; *) abs=$ORIG_PWD/$p ;; esac
  abs=$(printf '%s\n' "$abs" | lexnorm)
  # 1. The lexical string, before anything touches the filesystem.
  labs=$(printf '%s' "$abs" | lower)
  nr_abs_hit "$labs" && { echo "NEVER_READ:"; return; }
  # 2. The physical parent (resolves symlinks such as /tmp -> /private/tmp).
  d=$(dirname "$abs"); b=$(basename "$abs")
  if [ -d "$d" ]; then d=$(cd "$d" 2>/dev/null && pwd -P) || d=$(dirname "$abs"); abs=${d%/}/$b; fi
  labs=$(printf '%s' "$abs" | lower)
  nr_abs_hit "$labs" && { echo "NEVER_READ:"; return; }
  # 3. A symlinked leaf, inside OR outside the repo, is judged by its final
  # target, since reading the link reads the target: a never_read target, or a
  # chain that does not resolve, is refused before the OUTSIDE_REPO verdict.
  if [ -L "$abs" ]; then
    tgt=$(resolve_leaf "$abs")
    case $tgt in
      REFUSED:) echo "NEVER_READ:"; return ;;
      UNRESOLVED:) echo "UNRESOLVED:"; return ;;
    esac
    nr_abs_hit "$(printf '%s' "${tgt#OK:}" | lower)" && { echo "NEVER_READ:"; return; }
  fi
  case $labs in "$LREPO"/*) rel=${abs:$((${#REPO}+1))} ;; *) echo "OUTSIDE_REPO:$abs"; return ;; esac
  # Fold case to git's spelling (tracked, or deleted but still in the index).
  # The never_read excludes ride along: a literal pathspec naming a directory
  # enumerates its contents, and they must never include a never_read path.
  hit=$(git -c core.quotepath=off ls-files --full-name -- ":(literal,icase)$rel" "${NR_GIT_EXCL[@]}" | head -2)
  if [ -n "$hit" ] && [ "$(printf '%s\n' "$hit" | grep -c .)" = 1 ]; then echo "$hit"; return; fi
  # Untracked: fold case one component at a time against the directory listing.
  # Only on a fully normalised path, so a walk can never step into a directory
  # the never_read check above did not see.
  case /$rel/ in */../*|*/./*|*//*) echo "$rel"; return ;; esac
  cur=$REPO; part=""
  local IFS=/
  set -f
  for c in $rel; do
    m=$(ls -1a "$cur" 2>/dev/null | grep -ixF -- "$c" | head -1)
    [ -n "$m" ] || m=$c
    cur=$cur/$m; part=${part:+$part/}$m
  done
  set +f
  echo "$part"
}

# cfg_file_ok <path> <directive>: canonicalise-then-refuse a config-named file
# before it is read, scanned or run. The value is already lexically canonical
# and was checked against never_read at load, so only a symlinked component
# can change where it points: none -> no lookup needed; any -> the full
# canonicalisation (physical parent, never_read on the result).
cfg_file_ok() {
  local v=$1 acc="" c sym=0
  local IFS=/
  for c in $v; do acc=${acc:+$acc/}$c; [ -L "$acc" ] && { sym=1; break; }; done
  [ "$sym" = 1 ] || return 0
  IFS=$' \t\n'
  c=$(canon_path "$REPO/$1")
  case $c in
    NEVER_READ:) fail config_file "$2: $1 is never_read"; return 1 ;;
    UNRESOLVED:) fail config_file "$2: $1 is a symlink chain that does not resolve"; return 1 ;;
    OUTSIDE_REPO:*) fail config_file "$2: $1 resolves outside the repo (${c#OUTSIDE_REPO:})"; return 1 ;;
  esac
  return 0
}
# cfg_dir_ok <path> <label> [<probe>]: a root handed to a walker (ripgrep,
# ast-grep). Both FOLLOW a symlinked root, and the never_read prefix excludes
# are anchored to real paths, so a root that is, or passes through, a symlink
# is refused when its real target is outside the repo, is never_read, or is an
# ANCESTOR of a never_read prefix (the walk would reach the prefix under an
# alias no exclude matches). A symlinked LAST component is allowed only when
# it resolves to a regular file whose real path is inside the repo and passes
# real_ok: a walker then reads only that file.
# Builtins only unless a component is a symlink.
cfg_dir_ok() {
  local v=$1 lab=$2 f=${3:-config_file} rest=$1 acc="" c phys rel
  while [ -n "$rest" ]; do
    c=${rest%%/*}; acc=${acc:+$acc/}$c
    if [ -L "$acc" ]; then
      if [ ! -d "$acc" ]; then
        { [ "$acc" = "$v" ] && [ -f "$acc" ] && real_ok "$acc"; } && return 0
        fail "$f" "$lab: $v is a symlink that does not resolve to a readable file inside the repo; not walked"; return 1
      fi
      phys=$(cd "$acc" 2>/dev/null && pwd -P) || { fail "$f" "$lab: $v passes through a symlink that does not resolve; not walked"; return 1; }
      case $phys/ in "$REPO"/*) ;; *) fail "$f" "$lab: $v resolves outside the repo; not walked"; return 1 ;; esac
      rel=$(printf '%s' "${phys#"$REPO"}" | lower); rel=${rel#/}
      if never_read_hit "$rel" || nr_ancestor "$rel"; then
        fail "$f" "$lab: $v is a symlink to a directory that is, or contains, a never_read path; not walked"; return 1
      fi
    fi
    [ "$c" = "$rest" ] && break
    rest=${rest#*/}
  done
  return 0
}

# ── load the config (fail closed, before any path is resolved or read) ─────
config_fail() { echo "PROBE_FAILED=config ($1)"; exit 2; }
[ -e "$CONF_REL" ] || [ -L "$CONF_REL" ] || config_fail "$CONF_REL is absent"
[ -L .claude ] && config_fail ".claude is a symlink; refused"
[ -L "$CONF_REL" ] && config_fail "$CONF_REL is a symlink; refused"
{ [ -f "$CONF_REL" ] && [ -r "$CONF_REL" ]; } || config_fail "$CONF_REL is not a readable file"
cat "$CONF_REL" >"$T/config" 2>/dev/null || config_fail "$CONF_REL could not be read"
parse_config "$T/config" || config_fail "$CONF_REL: $CFG_ERR"
build_excludes
# Every REFUSE self-test line must refuse on every run. Pure string work, one
# awk and one tr for all of them; nothing is looked up.
: >"$T/st.refuse"; i=0
while [ $i -lt ${#ST_IN[@]} ]; do
  if [ "${ST_WANT[$i]}" = REFUSE ]; then
    v=${ST_IN[$i]}; case $v in '<repo>'*) v=$REPO${v#<repo>} ;; esac
    case $v in /*) ;; *) v=$REPO/$v ;; esac
    printf '%s\n' "$v" >>"$T/st.refuse"
  fi
  i=$((i+1))
done
if [ -s "$T/st.refuse" ]; then
  while IFS= read -r v; do
    case $v in "$LREPO"/*) v=${v:$((${#REPO}+1))} ;; esac
    never_read_hit "$v" || config_fail "$CONF_REL: a selftest_canon REFUSE line ($v) is not refused by the never_read set"
  done < <(lexnorm <"$T/st.refuse" | lower)
fi

# The 5 probes a config may leave unconfigured (importers, symbols and tables
# always run; without a control their values are labelled UNCONTROLLED).
PROBES_TOTAL=8
skipped_probes() { # -> "KEY directive" lines
  [ ${#OW_LABEL[@]} -gt 0 ] || [ ${#OWC_LABEL[@]} -gt 0 ] || echo "ONE_WAY one_way"
  [ ${#TR_GLOB[@]} -gt 0 ] || echo "TRIGGERS trigger"
  [ -n "$VEND_REG" ] || [ ${#VEND_INLINE[@]} -gt 0 ] || echo "VENDORED vendored_registry"
  [ -n "$DUAL_FROM" ] || [ ${#DUAL_INLINE[@]} -gt 0 ] || echo "DUAL_ACCESS dual_access_from"
  [ -n "$FLAG_RE" ] || echo "FLAGS flag_re"
}

if [ "$MODE" = selftest ]; then
  ORIG_PWD=$REPO; bad=0
  st() { # <label> <got> <want>
    if [ "$2" = "$3" ]; then echo "SELFTEST_PASS $1"; else echo "SELFTEST_FAIL $1 -> '$2' (want '$3')"; bad=1; fi
  }
  # 1. Config parsing and every fail-closed reason, on built-in strings.
  ci=0
  while IFS='|' read -r want body; do
    [ -n "$want" ] || continue
    ci=$((ci+1)); printf '%b' "$body" >"$T/st.$ci.conf"
    got=$( parse_config "$T/st.$ci.conf" && echo OK || echo "ERR $CFG_ERR" )
    case $got in "$want"*) echo "SELFTEST_PASS config: $want" ;; *) echo "SELFTEST_FAIL config case $ci -> '$got' (want '$want...')"; bad=1 ;; esac
  done <<'CASES'
ERR no 'version 1' line|# only a comment\n
ERR first directive must be 'version 1'|never_read a\nversion 1\nend\n
ERR bad version '2'|version 2\nend\n
ERR unknown directive 'bogus'|version 1\nbogus x\nend\n
ERR no 'end' line|version 1\nnever_read zz-st/private\n
ERR content after end|version 1\nend\nnever_read zz-st/private\n
ERR never_read: 'zz-st/*' must be a plain|version 1\nnever_read zz-st/*\nend\n
ERR never_read: 'zz-st/../x' must not contain '..'|version 1\nnever_read zz-st/../x\nend\n
ERR never_read: '/zz-st' must be a plain|version 1\nnever_read /zz-st\nend\n
ERR duplicate flag_re|version 1\nflag_re a\nflag_re b\nend\n
ERR env 'qa' has no trigger_env line|version 1\ntrigger x/* qa:deploy-x\nend\n
ERR 'zz-st/private/sub' is a configured path inside never_read|version 1\nnever_read zz-st/private\ncode_dirs zz-st/private/sub\nend\n
ERR bad ERE in flag_re: useFlag(|version 1\nflag_re useFlag(\nend\n
ERR bad ERE in flag_const_re|version 1\nflag_re ok\nflag_const_re a)(\nend\n
ERR bad ERE in one_way_content: create[[:space:]]+(policy|version 1\none_way_content rls * create[[:space:]]+(policy\nend\n
ERR bad ERE in note|version 1\nnote ( a note\nend\n
ERR bad ERE in trigger_note|version 1\ntrigger_env main TRIGGERS_MAIN always\ntrigger x/* main:d\ntrigger_note [a a note\nend\n
ERR bad ERE in tables_control|version 1\ntables_control a(b a label\nend\n
OK|version 1\r\n  # an indented comment\r\n\r\nnever_read ./ZZ-st//Private/\r\nnever_read zz-st/private\r\nend\r\n# trailing comment\n
CASES
  # The CR / comment / duplicate case parses to ONE lowercase, normalised entry.
  got=$( parse_config "$T/st.$ci.conf" && printf '%s,' "${NR_PREFIX[@]}" )
  st "config: CR lines, comments and a duplicate normalise to one entry" "$got" "zz-st/private,"
  # 2. SKIPPED: a config with no probe directives skips exactly the 5 optional probes.
  printf 'version 1\nend\n' >"$T/st.min.conf"
  got=$( parse_config "$T/st.min.conf" && skipped_probes | cut -d' ' -f1 | paste -sd, - )
  st "config: an empty config SKIPs ONE_WAY,TRIGGERS,VENDORED,DUAL_ACCESS,FLAGS" "$got" "ONE_WAY,TRIGGERS,VENDORED,DUAL_ACCESS,FLAGS"
  # Reported, not asserted: a project may leave probes unconfigured. A project
  # that must configure all of them pins this line in its own suite.
  echo "SELFTEST_NOTE probes configured: $((PROBES_TOTAL - $(skipped_probes | grep -c .)))/$PROBES_TOTAL"
  # 3. Derived variants of every never_read entry are refused on the string.
  derive() { # <prefix|any> <lowercase value> -> one input per line
    local v=$2 up; up=$(printf '%s' "$v" | tr '[:lower:]' '[:upper:]')
    if [ "$1" = prefix ]; then
      printf '%s\n' "$v" "$v/" "$v/x" "./$v/x" "$up/x" "zz/../$v/x" "$REPO/./$v/x"
      case $v in */*) printf '%s\n' "${v%%/*}//${v#*/}/x" ;; *) printf '%s\n' "./$v//x" ;; esac
    else
      printf '%s\n' "$v" "$v/" "$v/x" "./$v/x" "zz/$v" "zz/$v/x" "$up/x" "zz/$up/x" "zz/y/../$v/x" "zz//$v/x"
    fi
  }
  # A sibling that only shares the string is NOT refused (string-only check).
  sib() { if never_read_hit "$2"; then echo "SELFTEST_FAIL $1 sibling $2 is refused"; bad=1; else echo "SELFTEST_PASS $1 sibling $2 not refused"; fi; }
  for v in "${NR_PREFIX[@]}"; do
    derive prefix "$v" >"$T/st.derived"
    while IFS= read -r in; do st "derived(never_read $v) $in" "$(canon_path "$in")" "NEVER_READ:"; done <"$T/st.derived"
    sib "derived(never_read $v)" "${v}x/y"
  done
  for v in "${NR_ANY[@]}"; do
    derive any "$v" >"$T/st.derived"
    while IFS= read -r in; do st "derived(never_read_any $v) $in" "$(canon_path "$in")" "NEVER_READ:"; done <"$T/st.derived"
    sib "derived(never_read_any $v)" "zz/${v}x/y"; sib "derived(never_read_any $v)" "zz/x${v}/y"
  done
  [ ${#NR_PREFIX[@]} -gt 0 ] || [ ${#NR_ANY[@]} -gt 0 ] || echo "SELFTEST_NOTE no never_read entries configured: nothing to refuse"
  # 4. The config's own cases.
  i=0
  while [ $i -lt ${#ST_IN[@]} ]; do
    in=${ST_IN[$i]}; case $in in '<repo>'*) in=$REPO${in#<repo>} ;; esac
    want=${ST_WANT[$i]}; [ "$want" = REFUSE ] && want="NEVER_READ:"; case $want in OUTSIDE:*) want="OUTSIDE_REPO:${want#OUTSIDE:}" ;; esac
    st "config: $in" "$(canon_path "$in")" "$want"
    i=$((i+1))
  done
  # 5. Built-in shapes on this engine's own path, and a path outside the repo.
  case $SELF in
    "$REPO"/*/*) rel0=${SELF#"$REPO"/}; dir0=${rel0%/*}; base0=${rel0##*/}
      for in in "$rel0" "./$rel0" "$dir0/../$dir0/$base0" "$dir0//$base0" "$(printf '%s' "$rel0" | tr '[:lower:]' '[:upper:]')" "$REPO/./$rel0"; do
        st "built-in: $in" "$(canon_path "$in")" "$rel0"
      done ;;
    *) echo "SELFTEST_NOTE built-in own-path cases skipped: the engine is not inside the repo, in a subdirectory" ;;
  esac
  st "built-in: /nonexistent-outside/x.ts" "$(canon_path /nonexistent-outside/x.ts)" "OUTSIDE_REPO:/nonexistent-outside/x.ts"
  [ $bad = 0 ] && { echo "SELFTEST=pass"; exit 0; }
  echo "PROBE_FAILED=self_test"; exit 2
fi

# ── resolve the changed-file list and per-file content ──────────────────────
# $T/list: "<n>\t<path>"; $T/d/<n>.diff = changed lines (+/-); $T/d/<n>.full = current content
mkdir -p "$T/d"; : >"$T/list"
A=""; B=""
case $MODE in
  range)
    case $RANGE in *..*) A=${RANGE%%..*}; B=${RANGE##*..} ;; *) echo "PROBE_FAILED=usage (--range wants A..B)"; exit 2 ;; esac
    git rev-parse --verify --quiet "$A^{commit}" >/dev/null || { echo "PROBE_FAILED=git_range (bad base $A)"; exit 2; }
    git rev-parse --verify --quiet "$B^{commit}" >/dev/null || { echo "PROBE_FAILED=git_range (bad tip $B)"; exit 2; }
    git -c core.quotepath=off diff --name-only "$A" "$B" -- . "${NR_GIT_EXCL[@]}" >"$T/files.raw" || { echo "PROBE_FAILED=git_diff"; exit 2; } ;;
  staged)
    git -c core.quotepath=off diff --cached --name-only -- . "${NR_GIT_EXCL[@]}" >"$T/files.raw" || { echo "PROBE_FAILED=git_diff"; exit 2; } ;;
  files)
    : >"$T/files.raw"
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      rel=$(canon_path "$p")
      case $rel in
        OUTSIDE_REPO:*) fail outside_repo "${rel#OUTSIDE_REPO:}: not under $REPO, so triggers and importers cannot be evaluated"
                        out "OUTSIDE_REPO=${rel#OUTSIDE_REPO:}"; echo "${rel#OUTSIDE_REPO:}" >>"$T/files.raw" ;;
        NEVER_READ:) note "$NR_NOUN path refused unread"; out "$NR_KEY=1" ;;
        UNRESOLVED:) fail unresolved_link "$p: a symlink chain that does not resolve (a loop, or more than 8 hops); not read" ;;
        # A directory is never diffed, read or listed: its tree would name, and
        # its diff would read, everything under it.
        *) if [ -d "$rel" ]; then fail not_a_file "$rel: is a directory; pass the files in it"
           else echo "$rel" >>"$T/files.raw"; fi ;;
      esac
    done <"$T/files.in" ;;
esac

n=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if never_read_hit "$(printf '%s' "$p" | lower)"; then note "$NR_NOUN path refused unread"; out "$NR_KEY=1"; continue; fi
  # The working tree is read only in --files mode, and only after the fully
  # resolved real path (parent and symlinked leaf) has passed the refusal.
  if [ "$MODE" = files ]; then
    real_ok "$p"; r=$?
    case $r in
      0) ;;
      2) fail outside_read "$p: its real path is outside the repo; not read"; continue ;;
      *) note "$NR_NOUN path refused unread"; out "$NR_KEY=1"; continue ;;
    esac
  fi
  n=$((n+1)); printf '%s\t%s\n' "$n" "$p" >>"$T/list"
  case $MODE in
    range)
      git diff -U0 "$A" "$B" -- "$p" >"$T/d/$n.diff.raw" || fail git_diff "$p"
      git show "$B:$p" >"$T/d/$n.full" 2>/dev/null || git show "$A:$p" >"$T/d/$n.full" 2>/dev/null || : >"$T/d/$n.full" ;;
    staged)
      git diff --cached -U0 -- "$p" >"$T/d/$n.diff.raw" || fail git_diff "$p"
      git show ":$p" >"$T/d/$n.full" 2>/dev/null || git show "HEAD:$p" >"$T/d/$n.full" 2>/dev/null || : >"$T/d/$n.full" ;;
    files)
      if [ -f "$p" ]; then cat "$p" >"$T/d/$n.full"
      elif [ "$(git cat-file -t "HEAD:$p" 2>/dev/null)" = blob ]; then git show "HEAD:$p" >"$T/d/$n.full"; note "$p is deleted in the working tree (read from HEAD)"
      else : >"$T/d/$n.full"; fail missing_file "$p: not on disk and not in HEAD"; fi
      : >"$T/d/$n.diff.raw"
      if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
        git diff HEAD -U0 -- "$p" >"$T/d/$n.diff.raw" || fail git_diff "$p"
      fi
      # Untracked or unmodified: treat the whole file as the change.
      [ -s "$T/d/$n.diff.raw" ] || { sed 's/^/+/' "$T/d/$n.full" >"$T/d/$n.diff.raw"; echo "$p" >>"$T/synth"; } ;;
  esac
  grep -E '^[+-]' "$T/d/$n.diff.raw" | grep -vE '^(\+\+\+|---)( |$)' >"$T/d/$n.diff"
  rc=$?; [ $rc -le 1 ] || fail diff_lines "$p"
done <"$T/files.raw"
NFILES=$n
[ "$NFILES" = 0 ] && note "no changed files in scope (nothing staged, empty range, or only $NR_NOUN paths)"
cut -f2 "$T/list" >"$T/paths"

# ── tool resolution ─────────────────────────────────────────────────────────
SG=${BLAST_SG_BIN:-}
# Prefer ast-grep, and accept an `sg` only when it identifies as ast-grep: on
# Debian/Ubuntu /usr/bin/sg is shadow-utils' "execute as group", which fails
# every scan ("group 'scan' does not exist"). None found: importers fail below.
if [ -z "$SG" ]; then for c in ${BLAST_SG_CANDIDATES:-ast-grep /opt/homebrew/bin/ast-grep sg /opt/homebrew/bin/sg}; do command -v "$c" >/dev/null 2>&1 || continue; case ${c##*/} in sg) "$c" --version </dev/null 2>/dev/null | grep -q '^ast-grep' || continue ;; esac; SG=$c; break; done; fi
JQ=${BLAST_JQ_BIN:-jq}

TEXT_TOOL=""
RG=${BLAST_RG_BIN:-${RG_BIN:-}}
if [ -n "$RG" ]; then
  command -v "$RG" >/dev/null 2>&1 && TEXT_TOOL=rg || { fail text_search "rg binary $RG not found"; TEXT_TOOL=none; }
elif command -v rg >/dev/null 2>&1; then RG=rg; TEXT_TOOL=rg
else
  # The Claude Code binary bundles ripgrep and dispatches on argv0.
  for cand in "${CLAUDE_CODE_EXECPATH:-}" "$HOME/.local/bin/claude"; do
    [ -n "$cand" ] && [ -x "$cand" ] || continue
    printf '#!/bin/bash\nexec -a rg "%s" "$@"\n' "$cand" >"$T/rg"; chmod +x "$T/rg"
    if "$T/rg" --version 2>&1 | grep -q '^ripgrep'; then RG=$T/rg; TEXT_TOOL=rg; break; fi
  done
  [ -n "$TEXT_TOOL" ] || TEXT_TOOL=git-grep
fi

CODE_DIRS=(); CODE_DOT=0
if [ ${#CODE_DIRS_CFG[@]} -eq 0 ]; then CODE_DIRS=(.); CODE_DOT=1
else
  for d in "${CODE_DIRS_CFG[@]}"; do
    [ -d "$d" ] && cfg_dir_ok "$d" code_dirs && CODE_DIRS+=("$d")
  done
fi
FE_RE=""
for d in "${FE_DIRS[@]}"; do FE_RE="${FE_RE:+$FE_RE|}$(printf '%s' "$d" | sed 's/[.[\*^$()+?{|]/\\&/g')"; done

# text_files <ere>... : files under CODE_DIRS matching any pattern, case-insensitive.
# Excludes migrations, tests, dist and docs. rc 0 = ran (match or not), 2 = error.
text_files() {
  local p; local -a e
  e=(); for p in "$@"; do e+=(-e "$p"); done
  if [ "$TEXT_TOOL" = rg ]; then
    if [ "$CODE_DOT" = 1 ]; then
      "$RG" -l -i "${e[@]}" -g '!**/migrations/**' -g '!**/tests/**' -g '!**/__tests__/**' -g '!*.test.*' -g '!*.spec.*' -g '!**/dist*/**' -g '!*.md' "${RG_EXCL[@]}" -- . | sed 's|^\./||'
    else
      "$RG" -l -i "${e[@]}" -g '!**/migrations/**' -g '!**/tests/**' -g '!**/__tests__/**' -g '!*.test.*' -g '!*.spec.*' -g '!**/dist*/**' -g '!*.md' "${RG_EXCL[@]}" -- "${CODE_DIRS[@]}"
    fi
  else
    git grep -l -i -E "${e[@]}" -- "${CODE_DIRS[@]}" ':!**/migrations/**' ':!**/tests/**' ':!**/__tests__/**' ':!*.test.*' ':!*.spec.*' ':!**/dist*/**' ':!*.md' "${NR_GIT_EXCL[@]}"
  fi
  local rc=$?; [ $rc -le 1 ] && return 0; return 2
}
# text_words <word>... : "file:word" for whole-word hits, case-sensitive.
text_words() {
  local p; local -a e
  e=(); for p in "$@"; do e+=(-e "$p"); done
  if [ "$TEXT_TOOL" = rg ]; then
    if [ "$CODE_DOT" = 1 ]; then
      "$RG" -o -w -H --no-line-number "${e[@]}" -g '!**/migrations/**' -g '!*.md' "${RG_EXCL[@]}" -- . | sed 's|^\./||'
    else
      "$RG" -o -w -H --no-line-number "${e[@]}" -g '!**/migrations/**' -g '!*.md' "${RG_EXCL[@]}" -- "${CODE_DIRS[@]}"
    fi
  else
    git grep -o -w -h -H "${e[@]}" -- "${CODE_DIRS[@]}" ':!**/migrations/**' ':!*.md' "${NR_GIT_EXCL[@]}" 2>&1 | sed 's/^\([^:]*\):[0-9]*:/\1:/'
  fi
  local rc=$?; [ $rc -le 1 ] && return 0; return 2
}
# A value from a search with no positive control is labelled, never bare.
uncontrolled() { [ -n "$2" ] || printf 'UNCONTROLLED(no %s):' "$1"; }


# ═══ PROBE 1: one-way doors ═════════════════════════════════════════════════
if [ ${#OW_LABEL[@]} -eq 0 ] && [ ${#OWC_LABEL[@]} -eq 0 ]; then
  skipped ONE_WAY one_way
else
  : >"$T/oneway"
  while IFS="$(printf '\t')" read -r i p; do
    k=0
    while [ $k -lt ${#OW_GLOB[@]} ]; do
      case $p in ${OW_GLOB[$k]}) echo "${OW_LABEL[$k]}" ;; esac
      k=$((k+1))
    done
    k=0
    while [ $k -lt ${#OWC_GLOB[@]} ]; do
      case $p in
        ${OWC_GLOB[$k]}) grep -qiE -- "${OWC_RE[$k]}" "$T/d/$i.diff"; r=$?
          [ $r = 0 ] && echo "${OWC_LABEL[$k]}"
          [ $r -le 1 ] || fail one_way "${OWC_LABEL[$k]}: grep exit $r on $p" ;;
      esac
      k=$((k+1))
    done
  done <"$T/list" >"$T/oneway"
  ONEWAY=$(csv <"$T/oneway"); [ -n "$ONEWAY" ] || ONEWAY=none
  out "ONE_WAY=$ONEWAY"
fi

# ═══ PROBE 2: deploy triggers ══════════════════════════════════════════════
# classify <path> -> "<env> <trigger>" lines. First matching rule wins.
classify() {
  local p=$1 i=0 nr=${#TR_GLOB[@]} g rest svc tok
  while [ $i -lt $nr ]; do
    g=${TR_GLOB[$i]}; svc=""
    if [ "${TR_KIND[$i]}" = svc ]; then
      case $p in
        "$g"*/*) rest=${p#"$g"}; svc=${rest%%/*}
                 case ${TR_SVCS[$i]} in *",$svc,"*) ;; *) i=$((i+1)); continue ;; esac ;;
        *) i=$((i+1)); continue ;;
      esac
    else
      case $p in $g) ;; *) i=$((i+1)); continue ;; esac
    fi
    for tok in ${TR_OUT[$i]}; do
      tok=${tok//<svc>/$svc}
      echo "${tok%%:*} ${tok#*:}"
    done
    return
  done
}
if [ ${#TR_GLOB[@]} -eq 0 ]; then
  skipped TRIGGERS trigger
else
  # Self-test: the map must still classify known paths, or every verdict is suspect.
  TRIG_OK=1; k=0
  while [ $k -lt ${#TC_PATH[@]} ]; do
    classify "${TC_PATH[$k]}" | grep -qxF "${TC_WANT[$k]}" || TRIG_OK=0
    k=$((k+1))
  done
  [ "$TRIG_OK" = 1 ] || fail triggers "trigger-map self-test failed"
  TU=$(uncontrolled trigger_control "${TC_PATH[*]}")
  : >"$T/trig"
  if [ "$TRIG_OK" = 1 ]; then
    while IFS= read -r p; do classify "$p"; done <"$T/paths" >"$T/trig"
    k=0
    while [ $k -lt ${#TE_ENV[@]} ]; do
      v=$(grep "^${TE_ENV[$k]} " "$T/trig" | cut -d' ' -f2 | csv)
      j=0
      while [ $j -lt ${#TA_ENV[@]} ]; do
        [ "${TA_ENV[$j]}" = "${TE_ENV[$k]}" ] && v="${v:+$v,}${TA_NAME[$j]}(always)"
        j=$((j+1))
      done
      if [ "${TE_MODE[$k]}" = always ]; then out "${TE_KEY[$k]}=$TU${v:-none}"
      elif [ -n "$v" ]; then out "${TE_KEY[$k]}=$TU$v"; fi
      k=$((k+1))
    done
    k=0
    while [ $k -lt ${#TN_RE[@]} ]; do
      grep -qE -- "${TN_RE[$k]}" "$T/paths"; r=$?
      [ $r = 0 ] && note "${TN_TEXT[$k]}"
      [ $r -le 1 ] || fail triggers "trigger_note: grep exit $r"
      k=$((k+1))
    done
  fi
fi

# ═══ PROBE 3: vendored copies (registry from the config) ═══════════════════
: >"$T/vend"
if [ -z "$VEND_REG" ] && [ ${#VEND_INLINE[@]} -eq 0 ]; then
  skipped VENDORED vendored_registry
else
  : >"$T/registry"
  for e in "${VEND_INLINE[@]}"; do echo "$e" >>"$T/registry"; done
  reg_ok=1
  if [ -n "$VEND_REG" ]; then
    if cfg_file_ok "$VEND_REG" vendored_registry; then
      if [ -r "$VEND_REG" ]; then
        grep -oE '^[[:space:]]*"[^"]*\|[^"]*"' "$VEND_REG" | tr -d ' "' >"$T/registry.file"
        if [ -s "$T/registry.file" ]; then cat "$T/registry.file" >>"$T/registry"
        else fail vendored_registry "no entries parsed from ${VEND_REG##*/}"; reg_ok=0; fi
      else
        fail vendored_registry "$VEND_REG unreadable"; reg_ok=0
      fi
    else reg_ok=0; fi
  fi
  if [ "$reg_ok" = 1 ]; then
    while IFS= read -r p; do
      line=$(awk -F'|' -v p="$p" '{for(i=1;i<=NF;i++){ if (p==$i || index(p,$i"/")==1) {print; exit} }}' "$T/registry")
      [ -n "$line" ] || continue
      cnt=$(echo "$line" | awk -F'|' '{print NF-1}')
      echo "$p:canonical=$(echo "$line" | cut -d'|' -f1),copies=$cnt" >>"$T/vend"
    done <"$T/paths"
  fi
fi
k=0
while [ $k -lt ${#NOTE_RE[@]} ]; do
  grep -qE -- "${NOTE_RE[$k]}" "$T/paths"; r=$?
  [ $r = 0 ] && note "${NOTE_TEXT[$k]}"
  [ $r -le 1 ] || fail notes "note: grep exit $r"
  k=$((k+1))
done
[ -s "$T/vend" ] && out "VENDORED=$(cut -d: -f1 "$T/vend" | csv) ($(head -1 "$T/vend" | cut -d: -f2); guard: ${VEND_GUARD:-none configured})"

# ═══ PROBE 4: importers (ast-grep) + exported-symbol references (text) ══════
: >"$T/ts_stems"; : >"$T/py_stems"
stem_of() { local b; b=$(basename "$1"); b=${b%.*}; [ "$b" = index ] || [ "$b" = __init__ ] && b=$(basename "$(dirname "$1")"); echo "$b"; }
re_escape() { echo "$1" | sed 's/[.[\*^$()+?{|]/\\&/g'; }
in_dirs() { # <path> <dir>... : 0 if path is under one of the dirs
  local p=$1 d; shift
  for d in "$@"; do case $p in "$d"/*) return 0 ;; esac; done
  return 1
}
# scope_of <path> <ts|py> -> the importer scope of a changed file.
scope_of() {
  local p=$1 r x
  if [ "$2" = py ] && [ -n "$PY_SHARED" ]; then case $p in "$PY_SHARED"/*) echo allpy; return ;; esac; fi
  for r in "${SCOPE_ROOTS[@]}"; do
    case $p in "$r"/*/*) x=${p#"$r"/}; echo "$r/${x%%/*}"; return ;; esac
  done
  if [ "$2" = ts ]; then in_dirs "$p" "${FE_DIRS[@]}" && { echo frontend; return; }; echo "${p%%/*}"; return; fi
  case $p in */*) echo "${p%%/*}" ;; *) echo . ;; esac
}
while IFS= read -r p; do
  case $p in *.test.*|*.spec.*|*/tests/*|*/__tests__/*|*.d.ts) continue ;; esac
  case $p in
    *.ts|*.tsx|*.js|*.jsx|*.mjs) printf '%s\t%s\t%s\n' "$(scope_of "$p" ts)" "$(stem_of "$p")" "$p" >>"$T/ts_stems" ;;
    *.py) printf '%s\t%s\t%s\n' "$(scope_of "$p" py)" "$(stem_of "$p")" "$p" >>"$T/py_stems" ;;
  esac
done <"$T/paths"

: >"$T/importers"   # "<changed path>\t<importer file>"
run_sg() { # $1 key, $2 rules file, rest = paths. Writes $T/sg.<key>.tsv (ruleId\tfile\ttext) and .rc
  local key=$1 rules=$2; shift 2
  if "$SG" scan --rule "$rules" --json=stream "${SG_EXCL[@]}" "$@" >"$T/sg.$key.json" 2>"$T/sg.$key.err"; then
    "$JQ" -r '[.ruleId, .file, .text] | @tsv' <"$T/sg.$key.json" >"$T/sg.$key.tsv" 2>>"$T/sg.$key.err"
    echo $? >"$T/sg.$key.rc"
  else echo $? >"$T/sg.$key.rc"; fi
}
# ts_spec_matches <importer> <quoted spec> <changed path>: resolve the import
# spec and compare it to the changed module, so two modules sharing a stem in
# different directories are not conflated. Relative specs are resolved against
# the importer's directory; a configured ts_alias prefix is rewritten to its
# directory; any other bare spec must end in <parent-dir>/<stem>.
ts_spec_matches() {
  local f=$1 spec=$2 cp=$3 base r="" k e
  spec=${spec#[\'\"]}; spec=${spec%[\'\"]}
  for e in .js .jsx .ts .tsx .mjs; do spec=${spec%"$e"}; done
  spec=${spec%/index}
  base=${cp%.*}; base=${base%/index}
  case $spec in
    ./*|../*) r=$(printf '%s/%s\n' "$(dirname "$f")" "$spec" | awk -F/ '{n=0; for(i=1;i<=NF;i++){ if($i=="."||$i=="") continue; if($i==".."){ if(n>0) n--; continue }; a[++n]=$i }; o=a[1]; for(i=2;i<=n;i++) o=o"/"a[i]; print o}') ;;
    *) k=0
       while [ $k -lt ${#TS_ALIAS_P[@]} ]; do
         case $spec in "${TS_ALIAS_P[$k]}"*) r=${TS_ALIAS_R[$k]}${spec#"${TS_ALIAS_P[$k]}"}; break ;; esac
         k=$((k+1))
       done
       if [ -z "$r" ]; then
         case $spec in */"$(basename "$(dirname "$base")")/$(basename "$base")"|"$base") return 0 ;; esac; return 1
       fi ;;
  esac
  [ "$r" = "$base" ]
}
sg_ok=1
if [ -s "$T/ts_stems" ] || [ -s "$T/py_stems" ]; then
  if [ -z "$SG" ] || ! command -v "$SG" >/dev/null 2>&1; then fail importers "ast-grep not found${SG:+ ($SG)}"; sg_ok=0
  elif ! command -v "$JQ" >/dev/null 2>&1; then fail importers "jq not found ($JQ)"; sg_ok=0; fi
fi
TS_CTL_OK=0; PY_CTL_OK=0
if [ "$sg_ok" = 1 ] && [ -s "$T/ts_stems" ] && [ -n "$TS_CTL_FILE" ]; then cfg_file_ok "$TS_CTL_FILE" importers_ts_control && TS_CTL_OK=1; fi
if [ "$sg_ok" = 1 ] && [ -s "$T/py_stems" ] && [ -n "$PY_CTL_FILE" ]; then cfg_file_ok "$PY_CTL_FILE" importers_py_control && PY_CTL_OK=1; fi
IMP_UNCTL=""
if [ "$sg_ok" = 1 ] && [ -s "$T/ts_stems" ]; then
  [ "$TS_CTL_OK" = 1 ] || IMP_UNCTL=$(uncontrolled importers_ts_control "")
  for sc in $(cut -f1 "$T/ts_stems" | sort -u); do
    alt=$(awk -F'\t' -v s="$sc" '$1==s{print $2}' "$T/ts_stems" | sort -u | while read -r s; do re_escape "$s"; done | paste -sd'|' -)
    paths=()
    if [ "$sc" = frontend ]; then for d in "${FE_DIRS[@]}"; do [ -d "$d" ] && cfg_dir_ok "$d" frontend_dirs && paths+=("$d"); done
    else paths=("$sc"); fi
    key=ts.$(echo "$sc" | tr '/.' '__'); : >"$T/$key.yml"
    # A scope reached through a symlink into never_read is never scanned.
    if [ "$sc" != frontend ] && ! cfg_dir_ok "$sc" "importer scope" importers; then echo skip >"$T/sg.$key.rc"; continue; fi
    [ "$TS_CTL_OK" = 1 ] && paths+=("$TS_CTL_FILE")
    for lang in typescript tsx; do
      [ "$lang" = tsx ] && echo '---' >>"$T/$key.yml"
      cat >>"$T/$key.yml" <<EOF
id: imp-$lang
language: $lang
rule:
  kind: string
  regex: '(^[''"]|/)($alt)(\.js|\.ts|\.tsx)?[''"]\$'
  any:
    - inside: {kind: import_statement}
    - inside: {kind: export_statement}
    - inside: {kind: arguments}
EOF
      [ "$TS_CTL_OK" = 1 ] && cat >>"$T/$key.yml" <<EOF
---
id: ctl-$lang
language: $lang
rule:
  kind: string
  regex: '/$(re_escape "$TS_CTL_STEM")[''"]\$'
  inside: {kind: import_statement}
EOF
    done
    run_sg "$key" "$T/$key.yml" "${paths[@]}" &
  done
fi
if [ "$sg_ok" = 1 ] && [ -s "$T/py_stems" ]; then
  [ "$PY_CTL_OK" = 1 ] || IMP_UNCTL="$IMP_UNCTL$(uncontrolled importers_py_control "")"
  for sc in $(cut -f1 "$T/py_stems" | sort -u); do
    alt=$(awk -F'\t' -v s="$sc" '$1==s{print $2}' "$T/py_stems" | sort -u | while read -r s; do re_escape "$s"; done | paste -sd'|' -)
    paths=()
    case $sc in
      allpy) for d in "${PY_SHARED_PATHS[@]}"; do cfg_dir_ok "$d" importers_py_shared && paths+=("$d"); done ;;
      .) paths=(.) ;;
      *) paths=("$sc") ;;
    esac
    [ "$PY_CTL_OK" = 1 ] && paths+=("$PY_CTL_FILE")
    key=py.$(echo "$sc" | tr '/.' '__')
    case $sc in allpy|.) ;; *) cfg_dir_ok "$sc" "importer scope" importers || { echo skip >"$T/sg.$key.rc"; continue; } ;; esac
    cat >"$T/$key.yml" <<EOF
id: imp-py
language: python
rule:
  kind: dotted_name
  regex: '^(.*\.)?($alt)\$'
  any:
    - inside: {kind: import_statement, stopBy: end}
    - inside: {kind: import_from_statement, stopBy: end}
EOF
    [ "$PY_CTL_OK" = 1 ] && cat >>"$T/$key.yml" <<EOF
---
id: ctl-py
language: python
rule:
  kind: dotted_name
  regex: '^$(re_escape "$PY_CTL_MOD")\$'
  inside: {kind: import_from_statement, stopBy: end}
EOF
    run_sg "$key" "$T/$key.yml" "${paths[@]}" &
  done
fi

wait
if [ "$sg_ok" = 1 ] && [ -s "$T/ts_stems" ]; then
  for sc in $(cut -f1 "$T/ts_stems" | sort -u); do
    key=ts.$(echo "$sc" | tr '/.' '__')
    [ "$(cat "$T/sg.$key.rc")" = skip ] && continue
    if [ "$(cat "$T/sg.$key.rc")" = 0 ]; then
      if [ "$TS_CTL_OK" = 1 ] && ! grep -q '^ctl-' "$T/sg.$key.tsv"; then fail importers_ts "positive control ($TS_CTL_LABEL) did not match"; continue; fi
      grep '^imp-' "$T/sg.$key.tsv" | while IFS="$(printf '\t')" read -r _r f txt; do
        if [ "$sc" = frontend ]; then in_dirs "$f" "${FE_DIRS[@]}" || continue
        else case $f in "$sc"/*) ;; *) continue ;; esac; fi
        awk -F'\t' -v s="$sc" '$1==s{print $2"\t"$3}' "$T/ts_stems" | while IFS="$(printf '\t')" read -r st cp; do
          [ "$f" != "$cp" ] && ts_spec_matches "$f" "$txt" "$cp" && printf '%s\t%s\n' "$cp" "$f"
        done
      done >>"$T/importers"
    else
      fail importers_ts "ast-grep/jq exit $(cat "$T/sg.$key.rc") ($(head -c 160 "$T/sg.$key.err" | tr '\n' ' '))"
    fi
  done
fi
if [ "$sg_ok" = 1 ] && [ -s "$T/py_stems" ]; then
  for sc in $(cut -f1 "$T/py_stems" | sort -u); do
    key=py.$(echo "$sc" | tr '/.' '__')
    [ "$(cat "$T/sg.$key.rc")" = skip ] && continue
    if [ "$(cat "$T/sg.$key.rc")" = 0 ]; then
      if [ "$PY_CTL_OK" = 1 ] && ! grep -q '^ctl-' "$T/sg.$key.tsv"; then fail importers_py "positive control ($PY_CTL_LABEL) did not match"; continue; fi
      grep '^imp-' "$T/sg.$key.tsv" | while IFS="$(printf '\t')" read -r _r f txt; do
        case $sc in allpy|.) ;; *) case $f in "$sc"/*) ;; *) continue ;; esac ;; esac
        mod=${txt##*.}
        awk -F'\t' -v s="$sc" '$1==s{print $2"\t"$3}' "$T/py_stems" | while IFS="$(printf '\t')" read -r st cp; do
          [ "$mod" = "$st" ] && [ "$f" != "$cp" ] && printf '%s\t%s\n' "$cp" "$f"
        done
      done >>"$T/importers"
    else
      fail importers_py "ast-grep/jq exit $(cat "$T/sg.$key.rc") ($(head -c 160 "$T/sg.$key.err" | tr '\n' ' '))"
    fi
  done
fi
sort -u "$T/importers" -o "$T/importers"
# A changed file's importers that are themselves in the change set are noted, not hidden.
if [ -s "$T/importers" ]; then
  out "IMPORTERS_TOOL=ast-grep"
  cut -f1 "$T/importers" | sort | uniq -c | sort -rn | awk '{print $2":"$1}' >"$T/imp_counts"
  out "IMPORTERS=$IMP_UNCTL$(paste -sd, - <"$T/imp_counts")"
else
  if grep -q '^PROBE_FAILED=importers' "$T/failed"; then out "IMPORTERS=UNKNOWN(probe failed)"
  elif [ -s "$T/ts_stems" ] || [ -s "$T/py_stems" ]; then out "IMPORTERS=${IMP_UNCTL}none"; fi
fi

# Exported / top-level symbols added, changed or removed in the diff.
: >"$T/syms"
while IFS="$(printf '\t')" read -r i p; do
  case $p in *.test.*|*.spec.*|*/tests/*|*/__tests__/*|*/test_*.py) continue ;; esac
  case $p in *.ts|*.tsx|*.js|*.jsx)
    grep -E '^[+-][[:space:]]*export[[:space:]]+(default[[:space:]]+)?(declare[[:space:]]+)?(async[[:space:]]+)?(abstract[[:space:]]+)?(function\*?|const|let|var|class|type|interface|enum)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' "$T/d/$i.diff" \
      | sed -E 's/^([+-])[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(declare[[:space:]]+)?(async[[:space:]]+)?(abstract[[:space:]]+)?(function\*?|const|let|var|class|type|interface|enum)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*).*/\1 \7/' ;;
  *.py)
    grep -E '^[+-]((async[[:space:]]+)?def|class)[[:space:]]+[A-Za-z][A-Za-z0-9_]*|^[+-][A-Z][A-Z0-9_]{3,}[[:space:]]*(:[^=]*)?=' "$T/d/$i.diff" \
      | sed -E 's/^([+-])((async[[:space:]]+)?def|class)[[:space:]]+([A-Za-z0-9_]+).*/\1 \4/; s/^([+-])([A-Z][A-Z0-9_]+).*/\1 \2/' ;;
  esac | while read -r sign name; do
    [ ${#name} -ge 4 ] || continue
    printf '%s\t%s\t%s\n' "$name" "$sign" "$p"
  done >>"$T/syms"
done <"$T/list"
if [ -s "$T/syms" ]; then
  SYM_CAP=12
  # Order before the cap: names only on '-' lines (removed, or the old half of
  # a rename) first, since those are what break callers; then changed (both
  # signs); then added. Alphabetical within each group.
  awk -F'\t' '{ s[$1]=s[$1] $2 } END { for (n in s) { r = (s[n] !~ /\+/) ? 0 : ((s[n] ~ /-/) ? 1 : 2); print r "\t" n } }' "$T/syms" \
    | sort -t"$(printf '\t')" -k1,1n -k2,2 | cut -f2 >"$T/symall"
  head -$SYM_CAP "$T/symall" >"$T/symnames"
  n_sym=$(grep -c . "$T/symall")
  [ "$n_sym" -gt "$SYM_CAP" ] && out "SYMBOLS_NOT_SEARCHED=$((n_sym - SYM_CAP)) ($(tail -n +$((SYM_CAP+1)) "$T/symall" | csv))"
  if [ "$TEXT_TOOL" = none ]; then :
  else
    words=(); while IFS= read -r s; do words+=("$s"); done <"$T/symnames"
    # The control word rides in the same search, so it costs no extra process.
    SYM_CTL_OK=0; [ -n "$SYM_CTL_FILE" ] && cfg_file_ok "$SYM_CTL_FILE" symbols_control && SYM_CTL_OK=1
    [ "$SYM_CTL_OK" = 1 ] && words+=("$SYM_CTL_WORD")
    if text_words "${words[@]}" >"$T/symhits" 2>"$T/sym.err"; then
      if [ "$SYM_CTL_OK" = 1 ] && ! grep -qxF "$SYM_CTL_FILE:$SYM_CTL_WORD" "$T/symhits"; then
        fail symbols "positive control ($SYM_CTL_WORD in $SYM_CTL_FILE) did not match"
      else
        SU=""; [ "$SYM_CTL_OK" = 1 ] || SU=$(uncontrolled symbols_control "")
        : >"$T/symcounts"
        while read -r s; do
          # removed-only = present in '-' lines and not '+' lines
          signs=$(awk -F'\t' -v s="$s" '$1==s{print $2}' "$T/syms" | sort -u | tr -d '\n')
          state=changed; [ "$signs" = "-" ] && state=REMOVED; [ "$signs" = "+" ] && state=added
          awk -F'\t' -v s="$s" '$1==s{print $3}' "$T/syms" | grep -qxF -f "$T/synth" && state=in-file
          defs=$(awk -F'\t' -v s="$s" '$1==s{print $3}' "$T/syms" | sort -u)
          c=$(grep -E ":$s\$" "$T/symhits" | cut -d: -f1 | sort -u | grep -vxF "$defs" | grep -c .)
          echo "$s($state):$c" >>"$T/symcounts"
        done <"$T/symnames"
        out "SYMBOLS_TOOL=$TEXT_TOOL (whole-word, files outside the defining file)"
        # REMOVED first (every remaining reference is a break), then by reference count.
        out "SYMBOLS=$SU$( { grep '(REMOVED):' "$T/symcounts" | sort -t: -k2,2rn; grep -v '(REMOVED):' "$T/symcounts" | sort -t: -k2,2rn; } | paste -sd, -)"
      fi
    else
      fail symbols "$TEXT_TOOL error: $(head -c 160 "$T/sym.err" | tr '\n' ' ')"
    fi
  fi
fi

# ═══ PROBE 5: tables / RPCs touched, their readers, dual-access ═════════════
DUAL=""
if [ ${#DUAL_INLINE[@]} -gt 0 ]; then DUAL=$(printf '%s\n' "${DUAL_INLINE[@]}")
elif [ -n "$DUAL_FROM" ]; then
  if cfg_file_ok "$DUAL_FROM" dual_access_from; then
    DUAL=$(grep -F -A1 -- "$DUAL_ANCHOR" "$DUAL_FROM" 2>/dev/null | tail -1 | grep -oE '`[a-z_]+`' | tr -d '`')
    if [ "$(echo "$DUAL" | grep -c .)" -lt "$DUAL_MIN" ]; then fail dual_access_list "could not parse the list from $DUAL_FROM"; DUAL=""; fi
  fi
fi

STOP=" current_setting set_config coalesce nullif greatest least lower upper count sum max min avg array_agg string_agg jsonb_build_object json_build_object to_jsonb row_to_json gen_random_uuid uuidv7 date_trunc cast extract lateral generate_series jsonb_array_elements jsonb_each json_array_elements unnest select where set values the and only exists not table index public lateral unnest returning conflict nothing now epoch interval string current_date current_timestamp information_schema each json jsonb to with as on by of in if do new old excluded dual view views materialized function functions procedure routine routines sequence sequences type domain schema all delete update insert then else end case when rather database tables "
ID='"?[A-Za-z_][A-Za-z0-9_]*"?'
SCH="(${ID}\\.)?"
: >"$T/tables_diff"; : >"$T/tables_ctx"; : >"$T/tables_write"; : >"$T/tables_ddl"; : >"$T/rpcs"
extract_tables() { # $1 file, $2 kind(sql|py|ts), $3 "w" = write/DDL statements only, "d" = DDL targets only
  local src=$1
  if [ "$2" = sql ]; then
    # Drop comments, string literals and quoted identifiers containing spaces
    # (policy names), which otherwise read as "from their own rows".
    src=$T/sqlclean
    # Character scanner: drops /* */ and -- comments and '...' literals,
    # including ones that span lines (COMMENT ON ... IS '<prose>').
    awk '{ o=""; n=length($0); i=1
           while (i<=n) { ch=substr($0,i,1); two=substr($0,i,2)
             if (st=="c") { if (two=="*/") { st=""; i+=2 } else i++; continue }
             if (st=="q") { if (ch=="\047") st=""; i++; continue }
             if (two=="/*") { st="c"; i+=2; continue }
             if (two=="--") break
             if (ch=="\047") { st="q"; i++; continue }
             o=o ch; i++ }
           print o }' "$1" | sed -E "s/\"[^\"]*[[:space:]][^\"]*\"//g" >"$src"
  fi
  # The trailing \(? captures a following "(" so function calls
  # (current_setting(...), unnest(...)) can be dropped below.
  local X="$SCH$ID\\(?"
  # DDL on a relation: CREATE / ALTER / DROP / TRUNCATE / COMMENT ON a table,
  # view or materialized view, and REFRESH MATERIALIZED VIEW.
  local DDL="((create([[:space:]]+or[[:space:]]+replace)?|alter|drop|truncate|comment[[:space:]]+on)[[:space:]]+(table|(materialized[[:space:]]+)?view)|refresh[[:space:]]+materialized[[:space:]]+view([[:space:]]+concurrently)?)[[:space:]]+(if[[:space:]]+(not[[:space:]]+)?exists[[:space:]]+)?(only[[:space:]]+)?$X"
  local REL="(table[[:space:]]+|(materialized[[:space:]]+)?view[[:space:]]+)?"
  case $2${3:-} in
    sql) grep -oiE "$DDL|(insert[[:space:]]+into|update|delete[[:space:]]+from|from|join|references)[[:space:]]+$X|[[:space:]]on[[:space:]]+$REL$X" "$src" ;;
    sqlw) grep -oiE "$DDL|(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+$X|(policy|index|trigger|grant|revoke).*[[:space:]]on[[:space:]]+$REL$X" "$src" ;;
    sqld) grep -oiE "$DDL" "$src" ;;
    py|ts) grep -oE "(FROM|JOIN|INTO|UPDATE|TABLE|VIEW|REFERENCES)[[:space:]]+$X" "$src"
           [ "$2" = ts ] && grep -oE "\\.from\\([[:space:]]*['\"][A-Za-z_][A-Za-z0-9_]*" "$src" ;;
    pyw|tsw) grep -oE "(INSERT[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM|(CREATE|ALTER)[[:space:]]+TABLE|(CREATE([[:space:]]+OR[[:space:]]+REPLACE)?|ALTER)[[:space:]]+(MATERIALIZED[[:space:]]+)?VIEW)[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?$X" "$src" ;;
    pyd|tsd) grep -oE "((CREATE|ALTER)[[:space:]]+TABLE|(CREATE([[:space:]]+OR[[:space:]]+REPLACE)?|ALTER)[[:space:]]+(MATERIALIZED[[:space:]]+)?VIEW)[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?$X" "$src" ;;
  esac | grep -v '($' | sed -E 's/.*[[:space:].("'"'"']//; s/"//g' | lower | while read -r t; do
    case $STOP in *" $t "*) continue ;; esac
    case $t in pg_*|_*) continue ;; esac
    [ ${#t} -ge 3 ] && echo "$t"
  done
}
while IFS="$(printf '\t')" read -r i p; do
  case $p in
    *.sql) k=sql ;; *.py) k=py ;; *.ts|*.tsx) k=ts ;; *) continue ;;
  esac
  extract_tables "$T/d/$i.diff" $k d >>"$T/tables_ddl"
  extract_tables "$T/d/$i.diff" $k w >>"$T/tables_write"
  extract_tables "$T/d/$i.diff" $k >>"$T/tables_diff"
  [ $k = sql ] || extract_tables "$T/d/$i.full" $k >>"$T/tables_ctx"
  # A PostgREST client call: .rpc('fn').
  [ $k = ts ] && grep -oE "\\.rpc\\([[:space:]]*['\"][A-Za-z_][A-Za-z0-9_]*" "$T/d/$i.diff" | sed -E "s/.*['\"]//" >>"$T/rpcs"
done <"$T/list"
# by_freq: unique names, most-mentioned first (ties alphabetical). A relation
# the change really touches recurs; a stray keyword the extractor caught
# usually appears once, so it sinks within its tier.
by_freq() { grep -v '^$' | sort | uniq -c | sort -k1,1rn -k2,2 | awk '{print $2}'; }
by_freq <"$T/tables_diff" >"$T/tables_diff1"; mv "$T/tables_diff1" "$T/tables_diff"
by_freq <"$T/tables_ctx" >"$T/tables_ctx1"
grep -vxF -f "$T/tables_diff" "$T/tables_ctx1" >"$T/tables_ctx2"; [ $? -le 1 ] || fail tables "grep -f failed"
[ -s "$T/tables_diff" ] || cp "$T/tables_ctx1" "$T/tables_ctx2"   # grep -f with an empty pattern file matches nothing
# Rank in tiers: relations the change CREATES or ALTERS (table, view,
# materialized view), then ones it otherwise writes, then other changed
# lines, then the rest of each changed file (ctx). The reader search is
# capped, and the cap must cut the least relevant names, never a DDL target.
{ by_freq <"$T/tables_ddl"; by_freq <"$T/tables_write"; cat "$T/tables_diff" "$T/tables_ctx2"; } | grep -v '^$' | awk '!seen[$0]++' >"$T/tables_all"
TABLE_CAP=10
if [ -s "$T/tables_all" ] && [ "$TEXT_TOOL" != none ]; then
  # Positive control: the text tool must find a known reader of a known table.
  # All searches run in parallel (one process each); results are read back in order.
  if [ -n "$TAB_CTL_RE" ]; then
    ( text_files "$TAB_CTL_RE" >"$T/ctl" 2>"$T/ctl.err"; echo $? >"$T/ctl.rc" ) &
  fi
  head -$TABLE_CAP "$T/tables_all" >"$T/tables_q"; k=0
  while read -r t; do
    k=$((k+1)); te=$(re_escape "$t")
    ( text_files "(from|join|into|update|table)[[:space:]]+(\"?public\"?\\.)?\"?$te([^a-z0-9_]|\$)" "\\.from\\([[:space:]]*['\"]$te['\"]" >"$T/rd.$k" 2>"$T/rd.$k.err"; echo $? >"$T/rd.$k.rc" ) &
  done <"$T/tables_q"
  wait
  TBU=""; CTL_PASS=1
  if [ -n "$TAB_CTL_RE" ]; then { [ "$(cat "$T/ctl.rc")" = 0 ] && [ -s "$T/ctl" ]; } || CTL_PASS=0
  else TBU=$(uncontrolled tables_control ""); fi
  if [ "$CTL_PASS" = 1 ]; then
    : >"$T/tabout"; k=0
    while read -r t; do
      k=$((k+1))
      if [ "$(cat "$T/rd.$k.rc")" = 0 ]; then
        # Sorted: ripgrep returns files in thread order, and output must be deterministic.
        grep -vxF -f "$T/paths" "$T/rd.$k" | sort >"$T/rd2" || :
        c=$(grep -c . "$T/rd2")
        if [ -n "$FE_RE" ]; then fe=$(grep -cE "^($FE_RE)/" "$T/rd2"); else fe=0; fi; be=$((c - fe))
        # DUAL = the config's curated list; DUAL~derived = readers found in
        # both the frontend and a backend, but not on that list.
        tag=""; if echo "$DUAL" | grep -qx "$t"; then tag="DUAL"; elif [ "$fe" -gt 0 ] && [ "$be" -gt 0 ]; then tag="DUAL~derived"; fi
        if grep -qx "$t" "$T/tables_ddl"; then tag="${tag:+$tag;}ddl"; elif grep -qx "$t" "$T/tables_write"; then tag="${tag:+$tag;}write"; fi
        grep -qx "$t" "$T/tables_diff" || tag="${tag:+$tag;}ctx"
        echo "$t${tag:+[$tag]}(readers=$c fe=$fe be=$be)" >>"$T/tabout"
        sed "s|^|READER $t |" "$T/rd2" >>"$T/readers"
      else
        echo "PROBE_FAILED=table_readers ($t: $(head -c 120 "$T/rd.$k.err" | tr '\n' ' '))" >>"$T/failed"
      fi
    done <"$T/tables_q"
    out "TABLES_TOOL=$TEXT_TOOL (SQL keywords + .from('t'); ast-grep cannot see SQL in strings)"
    out "TABLES=$TBU$(paste -sd, - <"$T/tabout")"
    D=$( { grep -oE '^[a-z_0-9]+\[DUAL[];]' "$T/tabout" | sed -E 's/\[.*//'
           grep -oE '^[a-z_0-9]+\[DUAL~derived' "$T/tabout" | sed -E 's/\[.*/(derived)/'; } | csv)
    if [ -n "$DUAL_FROM" ] || [ ${#DUAL_INLINE[@]} -gt 0 ]; then out "DUAL_ACCESS=${D:-none}"; fi
    n_all=$(grep -c . "$T/tables_all")
    if [ "$n_all" -gt "$TABLE_CAP" ]; then out "TABLES_NOT_SEARCHED=$((n_all - TABLE_CAP)) ($(tail -n +$((TABLE_CAP+1)) "$T/tables_all" | csv))"; fi
  else
    fail table_readers "positive control ($TAB_CTL_LABEL) found nothing: $(head -c 120 "$T/ctl.err" | tr '\n' ' ')"
  fi
elif [ -s "$T/tables_all" ]; then
  out "TABLES=UNSEARCHED(text search unavailable):$(csv <"$T/tables_all")"
  if [ -n "$DUAL_FROM" ] || [ ${#DUAL_INLINE[@]} -gt 0 ]; then D=$(grep -xF "$(echo "$DUAL")" "$T/tables_all" | csv); out "DUAL_ACCESS=${D:-none}"; fi
else
  out "TABLES=none"
fi
[ -n "$DUAL_FROM" ] || [ ${#DUAL_INLINE[@]} -gt 0 ] || skipped DUAL_ACCESS dual_access_from
[ -s "$T/rpcs" ] && out "RPCS=$(csv <"$T/rpcs")"

# ═══ PROBE 6: feature flags in the changed files and their importers ════════
if [ -z "$FLAG_RE" ]; then
  skipped FLAGS flag_re
else
  # flag_names <file> <label>: the flag named by each flag_re hit. A grep exit
  # of 2 is a probe failure, never "no flags".
  flag_names() {
    local r h=$T/fl.hits
    grep -oE -- "$FLAG_RE" "$1" >"$h"; r=$?
    [ $r -le 1 ] || { fail flags "flag_re: grep exit $r"; return 0; }
    sed -E "s/.*['\"{]//" "$h" | sed "s/\$/($2)/"
  }
  # flag_consts <file> <label>: resolve each constant in the same file, else mark it.
  flag_consts() {
    [ -n "$FLAG_CONST_RE" ] || return 0
    local r h=$T/fc.hits
    grep -oE -- "$FLAG_CONST_RE" "$1" >"$h"; r=$?
    [ $r -le 1 ] || { fail flags "flag_const_re: grep exit $r"; return 0; }
    sed -E 's/.*[({[:space:]]//' "$h" | sort -u | while read -r c; do
      # The name comes from file content and goes into a pattern: identifiers only.
      case $c in ''|[0-9]*|*[!A-Za-z0-9_]*) echo "$c(unresolved)($2)"; continue ;; esac
      grep -oE -- "$c[[:space:]]*(:[^=]*)?=[[:space:]]*['\"][a-z0-9_-]+" "$1" >"$T/fc.val"; r=$?
      [ $r -le 1 ] || { fail flags "flag_consts: grep exit $r"; continue; }
      v=$(head -1 "$T/fc.val" | sed -E "s/.*['\"]//")
      echo "${v:-$c(unresolved)}($2)"
    done
  }
  : >"$T/flags"
  while IFS="$(printf '\t')" read -r i p; do
    flag_names "$T/d/$i.full" changed >>"$T/flags"
    flag_consts "$T/d/$i.full" changed >>"$T/flags"
  done <"$T/list"
  if [ -s "$T/importers" ]; then
    # Each importer is read only after never_read (lowercased in one pass) and,
    # when any component is a symlink, the full real-path check.
    cut -f2 "$T/importers" | sort -u | head -40 >"$T/imp40"
    lower <"$T/imp40" | paste "$T/imp40" - >"$T/imp40.l"
    while IFS="$(printf '\t')" read -r f lf; do
      [ -f "$f" ] || continue
      never_read_hit "$lf" && continue
      if has_link "$f"; then real_ok "$f" || continue; fi
      flag_names "$f" importer
      flag_consts "$f" importer
    done <"$T/imp40.l" >>"$T/flags"
  fi
  FL=$(sort -u "$T/flags" | csv); out "FLAGS=${FL:-none}"
fi

# ═══ PROBE 7 (full mode only): the configured guards ═══════════════════════
# A guard skipped here is reported as skipped, never as clean. Guards never
# run under --brief.
if [ "$BRIEF" = 0 ]; then
  if [ -z "$BANNED_GUARD" ]; then
    skipped BANNED_PATTERNS banned_guard
  else
    if [ "$GUARDS" = 1 ] && grep -qE '\.(ts|tsx|py|sql)$' "$T/paths"; then
      if [ "$TEXT_TOOL" != rg ]; then fail banned_patterns "needs ripgrep; text tool is $TEXT_TOOL"
      elif cfg_file_ok "$BANNED_GUARD" banned_guard; then
        RG_BIN=$RG bash "$BANNED_GUARD" >"$T/banned" 2>&1; brc=$?
        case $brc in 0) out "BANNED_PATTERNS=clean (rc=0)" ;; 1) out "BANNED_PATTERNS=FINDING (rc=1; details: $BANNED_GUARD)" ;;
          *) fail banned_patterns "rc=$brc: $(tail -2 "$T/banned" | tr '\n' ' ' | head -c 160)" ;; esac
      fi
    fi
    [ "$GUARDS" = 1 ] || out "BANNED_PATTERNS=SKIPPED (--guards runs $BANNED_GUARD)"
  fi
  if [ -s "$T/vend" ]; then
    if [ -z "$VEND_GUARD" ]; then skipped SHARED_DRIFT vendored_guard
    elif cfg_file_ok "$VEND_GUARD" vendored_guard; then
      bash "$VEND_GUARD" >"$T/drift" 2>&1; drc=$?
      if [ $drc = 0 ]; then out "SHARED_DRIFT=clean (rc=0)"; else out "SHARED_DRIFT=DRIFT (rc=$drc; details: $VEND_GUARD)"; fi
    fi
  fi
fi

# ═══ emit ═══════════════════════════════════════════════════════════════════
FAILED_N=$(grep -c . "$T/failed")
RC=0; [ "$FAILED_N" -gt 0 ] && RC=2
NOTES=$(sort -u "$T/notes" | paste -sd'|' - | sed 's/|/ | /g')

if [ "$BRIEF" = 1 ]; then
  # At most 12 lines. Lists are capped at 6 items, and what was cut is counted.
  # A SKIPPED probe's own line is replaced by the one folded SKIPPED line, so
  # the fold never adds a line.
  getk() { grep "^$1=" "$T/out" | head -1 | cut -d= -f2-; }
  issk() { case $1 in 'SKIPPED(not configured: '*) return 0 ;; esac; return 1; }
  capl() { local v=$1 total; total=$(echo "$v" | awk -F, '{print NF}')
    if [ "$total" -gt 6 ]; then echo "$(echo "$v" | cut -d, -f1-6),+$((total-6)) more (full: no --brief)"; else echo "$v"; fi; }
  SK=$(grep -E '^(ONE_WAY|TRIGGERS|VENDORED|DUAL_ACCESS|FLAGS)=SKIPPED\(not configured: ' "$T/out" | sed -E 's/^([A-Z_]+)=SKIPPED\(not configured: ([a-z_]+)\)$/\1(\2)/' | paste -sd, -)
  NSK=0; [ -n "$SK" ] && NSK=$(echo "$SK" | awk -F, '{print NF}')
  echo "BLAST_RADIUS mode=$MODE files=$NFILES text_tool=$TEXT_TOOL rc=$RC evaluated=$((PROBES_TOTAL - NSK))/$PROBES_TOTAL"
  v=$(getk ONE_WAY); [ -n "$v" ] && ! issk "$v" && echo "ONE_WAY=$v"
  tl=""; k=0
  while [ $k -lt ${#TE_ENV[@]} ]; do
    if [ "${TE_MODE[$k]}" = always ]; then v=$(getk "${TE_KEY[$k]}"); tl="$tl${v:+x}"; fi
    k=$((k+1))
  done
  if [ -n "$tl" ]; then
    line=""; k=0
    while [ $k -lt ${#TE_ENV[@]} ]; do
      [ "${TE_MODE[$k]}" = always ] && { v=$(getk "${TE_KEY[$k]}"); line="${line:+$line }${TE_KEY[$k]}=${v:-?}"; }
      k=$((k+1))
    done
    echo "$line"
  fi
  for k in DUAL_ACCESS TABLES IMPORTERS SYMBOLS FLAGS VENDORED; do
    v=$(getk $k); [ -n "$v" ] || continue
    issk "$v" && continue
    line="$k=$(capl "$v")"
    ns=$(getk ${k}_NOT_SEARCHED); [ -n "$ns" ] && line="$line ${k}_NOT_SEARCHED=${ns%% *}"
    echo "$line"
  done
  [ -n "$SK" ] && echo "SKIPPED=$SK [not configured in $CONF_REL: NOT 'none']"
  extra=""; v=$(getk OUTSIDE_REPO); [ -n "$v" ] && extra="OUTSIDE_REPO=$v"
  if [ -n "$extra" ] && [ -n "$NOTES" ]; then echo "NOTES=$extra | $NOTES"; elif [ -n "$extra$NOTES" ]; then echo "NOTES=$extra$NOTES"; fi
  [ "$FAILED_N" -gt 0 ] && echo "PROBE_FAILED=$(sed 's/^PROBE_FAILED=//' "$T/failed" | paste -sd';' - | sed 's/;/; /g') [a failed probe is NOT 'nothing found']"
  echo "NEXT=Repo rule: the /blast-radius skill reads the flagged readers, names the fact this change is safe because of, and proves that fact by running something."
else
  echo "BLAST_RADIUS mode=$MODE files=$NFILES text_tool=$TEXT_TOOL sg=${SG:-none}"
  echo "## changed"; sed 's/^/FILE=/' "$T/paths"
  echo "## findings"; cat "$T/out"
  if [ -s "$T/importers" ]; then echo "## importers (ast-grep)"; awk -F'\t' '{print "IMPORTER "$1" <- "$2}' "$T/importers"; fi
  if [ -s "$T/readers" ]; then echo "## table readers ($TEXT_TOOL)"; cat "$T/readers"; fi
  if [ -s "$T/vend" ]; then echo "## vendored"; sed 's/^/VENDORED_FILE=/' "$T/vend"; fi
  [ -n "$NOTES" ] && { echo "## notes"; sed 's/^/NOTE=/' "$T/notes"; }
  [ "$FAILED_N" -gt 0 ] && { echo "## probe failures (NOT 'nothing found')"; cat "$T/failed"; }
  echo "RC=$RC"
fi
exit $RC
