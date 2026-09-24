#!/usr/bin/env bash
# init.sh — one-command staging for the ve-kit bootstrap
#
# Run this from inside the project directory you want to set up:
#
#   curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash
#
# Or clone + run:
#
#   git clone --depth 1 https://github.com/HuntsDesk/ve-kit.git .ve-kit-src
#   bash .ve-kit-src/init.sh
#
# What it does:
#   1. Clones ve-kit into `.ve-kit/` inside your project (shallow clone)
#   2. Writes the exact Claude Code prompt to `.ve-kit/PROMPT.txt`
#   3. Prints next steps
#
# Idempotent: re-running refreshes `.ve-kit/` to the latest main. Never
# touches `.claude/`, `CLAUDE.md`, or anything outside `.ve-kit/`. The
# bootstrap protocol (run by Claude Code, not this script) is what actually
# sets up your project.

set -euo pipefail

# Require bash (not sh). If someone pipes this into `sh`, bail before we hit
# bashisms.
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "ve-kit init.sh needs bash. Run: curl … | bash  (not | sh)" >&2
  exit 1
fi

KIT_REPO="${VE_KIT_REPO:-https://github.com/HuntsDesk/ve-kit.git}"
KIT_BRANCH="${VE_KIT_BRANCH:-main}"
# Pin a specific commit for reproducibility:
#   VE_KIT_COMMIT=<sha> curl … | bash
KIT_COMMIT="${VE_KIT_COMMIT:-}"
STAGE_DIR="${VE_KIT_STAGE:-.ve-kit}"

BOLD=$(tput bold 2>/dev/null || echo "")
DIM=$(tput dim 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

say() { printf '%s\n' "${BLUE}${BOLD}[ve-kit]${RESET} $*"; }
ok()  { printf '%s\n' "${GREEN}${BOLD}✓${RESET} $*"; }
warn(){ printf '%s\n' "${YELLOW}${BOLD}!${RESET} $*"; }

# --- Preflight checks ------------------------------------------------------
for bin in git curl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ve-kit init needs '$bin' — please install it and retry." >&2
    exit 1
  fi
done

TARGET_DIR="$(pwd)"
say "Setting up ve-kit in: ${TARGET_DIR}"

# --- Refuse to overwrite an in-progress setup ------------------------------
# If STAGE_DIR/.git exists, verify it's OUR clone before any reset --hard.
# Resetting a user's unrelated git repo that happens to live at .ve-kit/
# would be destructive — bail with a clear error instead.
if [[ -d "$STAGE_DIR/.git" ]]; then
  EXISTING_ORIGIN=$(git -C "$STAGE_DIR" remote get-url origin 2>/dev/null || echo "")
  # Accept both URL forms (with/without .git) for safety.
  if [[ "$EXISTING_ORIGIN" != "$KIT_REPO" && "$EXISTING_ORIGIN" != "${KIT_REPO%.git}" ]]; then
    echo "${STAGE_DIR}/ is a git clone, but its origin is '${EXISTING_ORIGIN}'" >&2
    echo "(expected ${KIT_REPO})." >&2
    echo "Refusing to touch it. Move or rename your existing ${STAGE_DIR}/ first," >&2
    echo "or set VE_KIT_STAGE=a-different-dir when running init.sh." >&2
    exit 1
  fi
  say "Found existing ve-kit clone at ${STAGE_DIR}/ — refreshing"
  git -C "$STAGE_DIR" fetch --depth 1 origin "$KIT_BRANCH" >/dev/null 2>&1
  git -C "$STAGE_DIR" reset --hard "origin/$KIT_BRANCH" >/dev/null 2>&1
  ok "${STAGE_DIR}/ refreshed to latest ${KIT_BRANCH}"
elif [[ -e "$STAGE_DIR" ]]; then
  echo "${STAGE_DIR} exists but isn't a ve-kit clone. Remove it or set VE_KIT_STAGE=different-dir." >&2
  exit 1
else
  say "Cloning ve-kit into ${STAGE_DIR}/ (shallow)"
  git clone --depth 1 --branch "$KIT_BRANCH" "$KIT_REPO" "$STAGE_DIR" >/dev/null 2>&1
  ok "Cloned ${KIT_REPO}#${KIT_BRANCH} → ${STAGE_DIR}/"
fi

# Optional: pin to a specific commit for reproducibility.
if [[ -n "$KIT_COMMIT" ]]; then
  say "Pinning to commit ${KIT_COMMIT}"
  git -C "$STAGE_DIR" fetch --depth 1 origin "$KIT_COMMIT" >/dev/null 2>&1 || true
  git -C "$STAGE_DIR" checkout --quiet "$KIT_COMMIT" >/dev/null 2>&1
  ok "Checked out ${KIT_COMMIT}"
fi

# --- Detect if user already has a .claude/ setup ---------------------------
UPGRADE_MODE=0
if [[ -d ".claude" ]] || [[ -f "CLAUDE.md" ]]; then
  UPGRADE_MODE=1
fi

# --- Write the exact prompt the user will paste into Claude Code -----------
PROMPT_FILE="$STAGE_DIR/PROMPT.txt"

if [[ "$UPGRADE_MODE" == 1 ]]; then
  cat > "$PROMPT_FILE" <<'EOF'
Read @.ve-kit/01-BOOTSTRAP.md and run it in UPGRADE mode against this
project (I already have a .claude/ config). Follow the protocol to diff
my existing setup against the current ve-kit, show me what's new/changed,
and ask which upgrades I want to apply.

Default choices unless I say otherwise:
- Keep my existing CLAUDE.md content; add any new sections from the template
- Add any missing rule files under .claude/rules/
- Add any missing hook scripts under .claude/hooks/
- Install all starter skills (plan, review, go, /review-* family, /bootstrap)
- Skip the Vibe Board setup if I don't already have one (ask me first)

Self-verify at the end and report pass/fail.
EOF
else
  cat > "$PROMPT_FILE" <<'EOF'
Read @.ve-kit/01-BOOTSTRAP.md and set up this project following the
protocol. I want Layer 1 (foundation) + Layer 2 (Vibe Board).

Walk me through Phase 0 prerequisites first (check for gcloud, firebase,
node, claude CLI; tell me what's missing). Then ask me the Phase 1
project questions (name, description, main language, GCP project ID,
default branch, anything to add to the deny list).

Once you have my answers, execute all phases end to end. Self-verify at
the end and report pass/fail.

If I also want the Docker worker later, I'll ask you to add Layer 3
from @.ve-kit/03-VE-WORKER.md after the base is working.
EOF
fi
ok "Wrote Claude Code prompt → ${STAGE_DIR}/PROMPT.txt"

# --- Optionally suggest adding to .gitignore -------------------------------
if [[ -f ".gitignore" ]]; then
  if ! grep -qE "^\.ve-kit/?$" .gitignore 2>/dev/null; then
    warn "Consider adding ${STAGE_DIR}/ to .gitignore (it's staging — not something to commit)"
  fi
fi

# --- Print next steps ------------------------------------------------------
cat <<EOF

${BOLD}${GREEN}ve-kit is staged. Next steps:${RESET}

${BOLD}1.${RESET} Open Claude Code in this directory:
     ${DIM}claude${RESET}

${BOLD}2.${RESET} Paste the prompt from ${DIM}${STAGE_DIR}/PROMPT.txt${RESET}
     ${DIM}(cat ${STAGE_DIR}/PROMPT.txt | pbcopy${RESET}  on macOS, or just open the file)

     For reference, here's the prompt content:

EOF

sed 's/^/     /' "$PROMPT_FILE"

cat <<EOF

${BOLD}3.${RESET} Answer Claude's questions. Setup takes ~15-20 min.

${BOLD}4.${RESET} When Claude reports ${DIM}"Your setup is complete"${RESET}, you're done.
     You can remove the staging dir: ${DIM}rm -rf ${STAGE_DIR}/${RESET}

EOF

if [[ "$UPGRADE_MODE" == 1 ]]; then
  cat <<EOF
${YELLOW}${BOLD}Note:${RESET} detected an existing ${DIM}.claude/${RESET} or ${DIM}CLAUDE.md${RESET} — the prompt
above runs in upgrade mode. Nothing in your current setup will be
overwritten without your confirmation.

EOF
fi

ok "Ready."
