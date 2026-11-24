#!/bin/bash
# Pull, test, build, and cleanly restart Gary Tools (app + background daemon).
#
# Usage:
#   ./update.sh                  Pull latest (ff-only), test, build, and restart
#   ./update.sh --check          Fetch origin and report if updates are available (no changes)
#   ./update.sh --local          Skip git pull; test, build, and restart working tree
#   ./update.sh --skip-tests     Skip ./test.sh (faster local iteration)
#   ./update.sh --setup-signing  Ensure local code signing certificate is set up first
#   ./update.sh --applications   Install built app to /Applications/Gary Tools.app
#   ./update.sh --local-dist     Run directly from dist/Gary Tools.app
#   ./update.sh --no-sudo        Skip interactive pmset sudoers setup in install.sh
#   ./update.sh --push           After tests and build pass, push verified commits to origin
set -euo pipefail

# Resolve symlinks (so ~/.local/bin/gary-tools-update works from anywhere)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  LINK_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$LINK_DIR/$SOURCE"
done
DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
cd "$DIR"

DO_PULL=yes
DO_TESTS=yes
DO_SIGN_SETUP=no
DO_PUSH=no
DO_CHECK=no
INSTALL_DEST=""
NO_SUDO=no

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local|--no-pull) DO_PULL=no ;;
    --skip-tests)      DO_TESTS=no ;;
    --setup-signing)   DO_SIGN_SETUP=yes ;;
    --push)            DO_PUSH=yes ;;
    --check)           DO_CHECK=yes ;;
    --applications)    INSTALL_DEST="--applications" ;;
    --local-dist)      INSTALL_DEST="--local-dist" ;;
    --no-sudo)         NO_SUDO=yes ;;
    -h|--help)         usage; exit 0 ;;
    *)                 printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Check-only mode (read-only fetch + parseable status) ──
if [ "$DO_CHECK" = yes ]; then
  git fetch --prune --quiet origin
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [ -z "$UPSTREAM" ]; then
    if [ "$BRANCH" != "HEAD" ] && git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null 2>&1; then
      UPSTREAM="origin/$BRANCH"
    elif git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
      UPSTREAM="origin/main"
    else
      die "No upstream tracking branch or origin/main found."
    fi
  fi

  LOCAL_SHA=$(git rev-parse --short HEAD)
  REMOTE_SHA=$(git rev-parse --short "$UPSTREAM")
  BEHIND=$(git rev-list --count "HEAD..$UPSTREAM")

  if [ "$BEHIND" -gt 0 ]; then
    echo "STATUS=update_available"
  else
    echo "STATUS=up_to_date"
  fi
  echo "BRANCH=$BRANCH"
  echo "UPSTREAM=$UPSTREAM"
  echo "LOCAL_SHA=$LOCAL_SHA"
  echo "REMOTE_SHA=$REMOTE_SHA"
  echo "BEHIND=$BEHIND"
  if [ "$BEHIND" -gt 0 ]; then
    git log --format='%h %s' "HEAD..$UPSTREAM"
  fi
  exit 0
fi

if [ "$DO_SIGN_SETUP" = yes ]; then
  chmod +x "$DIR/scripts/setup-signing.sh"
  "$DIR/scripts/setup-signing.sh"
fi

# ── 1. Pull latest (fast-forward only) ──
if [ "$DO_PULL" = yes ]; then
  if [ -n "$(git status --porcelain)" ]; then
    die "Working tree has uncommitted changes. Commit/stash them first, or re-run with --local."
  fi
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  BEFORE=$(git rev-parse HEAD)
  say "Pulling latest on $BRANCH"
  git fetch --prune origin
  git pull --ff-only
  AFTER=$(git rev-parse HEAD)
  if [ "$BEFORE" != "$AFTER" ]; then
    say "New commits:"
    git log --oneline "$BEFORE..$AFTER"
  else
    say "Already up to date ($(git rev-parse --short HEAD))"
  fi
fi

# ── 2. Run test suite before touching the running app ──
if [ "$DO_TESTS" = yes ]; then
  say "Running test suite"
  chmod +x "$DIR/test.sh"
  "$DIR/test.sh"
else
  warn "Skipping tests (--skip-tests)"
fi

# ── 3. Auto-detect /Applications install from LaunchAgent if not explicitly overridden ──
DAEMON_PLIST="$HOME/Library/LaunchAgents/com.$(whoami).garytools.daemon.plist"
if [ -z "$INSTALL_DEST" ] && [ -f "$DAEMON_PLIST" ]; then
  PLIST_PROG=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$DAEMON_PLIST" 2>/dev/null || true)
  case "$PLIST_PROG" in
    "/Applications/Gary Tools.app/"*) INSTALL_DEST="--applications" ;;
  esac
fi

INSTALL_ARGS=()
[ -n "$INSTALL_DEST" ] && INSTALL_ARGS+=("$INSTALL_DEST")
[ "$NO_SUDO" = yes ] && INSTALL_ARGS+=(--no-sudo)

# ── 4. Build, cleanly restart app & daemon, and verify ──
chmod +x "$DIR/install.sh"
"$DIR/install.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}

# ── 5. Optional verified push ──
if [ "$DO_PUSH" = yes ]; then
  if [ -n "$(git status --porcelain)" ]; then
    die "Cannot --push with uncommitted changes."
  fi
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  say "Pushing verified $BRANCH to origin"
  git push origin "$BRANCH"
fi
