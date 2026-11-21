#!/bin/bash
# dev-pull-all.sh — fast-forward pull git repos under ~/Developer (and one subfolder deep, e.g. local/).
# Never merges, rebases, pushes, or overwrites uncommitted work.
#
# Usage:
#   dev-pull-all.sh [--format plain|antigravity|log] [--always] [--dir PATH]
#
# Modes:
#   plain       (default) Human-readable report for Claude Code / Codex SessionStart hooks or CLI.
#   antigravity JSON output for Antigravity SessionStart hook (~/.gemini/config/hooks.json).
#   log         Compact one-line summary for background runners (e.g. lidguard).
#
# Without --always, checks stdin JSON (cwd / workspacePaths) and exits cleanly if the session
# is not inside the target Developer directory.

FORMAT="plain"
ALWAYS=no
DEV="$HOME/Developer"

while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="${2:-plain}"; shift 2 ;;
    --always) ALWAYS=yes; shift ;;
    --dir)    DEV="${2:-$DEV}"; shift 2 ;;
    *)        shift ;;
  esac
done

# Expand leading ~ if passed
DEV="${DEV/#\~/$HOME}"
DEV="${DEV%/}"

JQ=$(command -v jq 2>/dev/null || echo /usr/bin/jq)

emit_empty() {
  if [ "$FORMAT" = "antigravity" ]; then
    printf '{}\n'
  fi
  exit 0
}

emit_report() {
  local msg="$1"
  case "$FORMAT" in
    antigravity)
      if [ -x "$JQ" ]; then
        "$JQ" -n --arg msg "$msg" '{"injectSteps":[{"systemMessage":{"systemMessage":$msg}}]}'
      else
        python3 -c 'import json,sys; print(json.dumps({"injectSteps":[{"systemMessage":{"systemMessage":sys.argv[1]}}]}))' "$msg"
      fi
      ;;
    *)
      printf '%s\n' "$msg"
      ;;
  esac
}

# In hook mode (without --always), only run when the session is inside $DEV
if [ "$ALWAYS" != "yes" ]; then
  input=""
  if [ ! -t 0 ]; then
    input=$(cat)
  fi
  matched=no
  check_path() {
    local p="${1%/}"
    case "$p" in
      "$DEV"|"$DEV"/*) matched=yes ;;
    esac
  }
  if [ -n "$input" ] && [ -x "$JQ" ]; then
    cwd=$(printf '%s' "$input" | "$JQ" -r '.cwd // empty' 2>/dev/null)
    [ -n "$cwd" ] && check_path "$cwd"
    while IFS= read -r wp; do
      [ -n "$wp" ] && check_path "$wp"
    done < <(printf '%s' "$input" | "$JQ" -r '.workspacePaths[]? // empty' 2>/dev/null)
  fi
  if [ "$matched" = "no" ] && [ -z "${cwd:-}" ]; then
    check_path "$PWD"
  fi
  [ "$matched" = "yes" ] || emit_empty
fi

[ -d "$DEV" ] || emit_empty

# Prevent overlapping runs between LidGuard and SessionStart hooks
LOCKDIR="/tmp/dev-pull-all.lock"
HAVE_LOCK=no
TMP=""

cleanup() {
  [ -n "$TMP" ] && rm -rf "$TMP"
  [ "$HAVE_LOCK" = "yes" ] && rm -rf "$LOCKDIR"
}
trap cleanup EXIT

acquire_lock() {
  local attempts=0 max_attempts=40
  [ "$ALWAYS" = "yes" ] && max_attempts=1
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    local pid="" mtime=0 now
    pid=$(cat "$LOCKDIR/pid" 2>/dev/null || true)
    now=$(date +%s)
    mtime=$(stat -f %m "$LOCKDIR" 2>/dev/null || echo "$now")
    # Reclaim stale lock if owning process is gone or lock is older than 5 minutes
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ $((now - mtime)) -gt 300 ]; then
      rm -rf "$LOCKDIR" 2>/dev/null || true
      continue
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      return 1
    fi
    sleep 0.5
  done
  echo $$ > "$LOCKDIR/pid"
  HAVE_LOCK=yes
  return 0
}

if ! acquire_lock; then
  if [ "$FORMAT" = "log" ]; then
    echo "skipped (sync already running)"
  fi
  emit_empty
fi

export GIT_TERMINAL_PROMPT=0
TMP=$(mktemp -d)

sync_repo() {
  local dir="$1" rel safe before after err note=""
  rel="${dir#$DEV/}"
  safe="${rel//\//__}"

  if ! git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    note="not pulled (no upstream branch)"
  else
    before=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    if err=$(git -C "$dir" pull --ff-only --quiet 2>&1); then
      after=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
      if [ "$before" != "$after" ]; then
        local commits
        commits=$(git -C "$dir" rev-list --count "$before..$after" 2>/dev/null || echo "?")
        note="updated (+${commits} commits)"
        printf '%s\n' "$rel" > "$TMP/updated.$safe"
      fi
    else
      note="PULL FAILED: $(printf '%s' "$err" | tail -1)"
      printf '%s\n' "$rel" > "$TMP/failed.$safe"
    fi
  fi

  local dirty unpushed work=""
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  unpushed=$(git -C "$dir" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
  [ "$dirty" != "0" ] && work="$dirty uncommitted file(s)"
  [ "$unpushed" != "0" ] && work="${work:+$work, }$unpushed unpushed commit(s)"
  [ -n "$work" ] && note="${note:+$note; }$work on $(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$note" ] && printf -- '- %s: %s\n' "$rel" "$note" > "$TMP/note.$safe"
  return 0
}

# Find repos directly in $DEV/* and one grouping folder deep ($DEV/*/*),
# never descending into a directory that is already a git repo.
count=0
for d in "$DEV"/*; do
  [ -d "$d" ] || continue
  if [ -e "$d/.git" ]; then
    count=$((count + 1))
    sync_repo "$d" &
  else
    for sub in "$d"/*; do
      [ -d "$sub" ] && [ -e "$sub/.git" ] || continue
      count=$((count + 1))
      sync_repo "$sub" &
    done
  fi
done
wait

if [ "$FORMAT" = "log" ]; then
  updated_list=$(cat "$TMP"/updated.* 2>/dev/null | sort | paste -sd ', ' - || true)
  failed_list=$(cat "$TMP"/failed.* 2>/dev/null | sort | paste -sd ', ' - || true)
  updated_n=$(ls "$TMP"/updated.* 2>/dev/null | wc -l | tr -d ' ')
  failed_n=$(ls "$TMP"/failed.* 2>/dev/null | wc -l | tr -d ' ')
  if [ "$updated_n" -gt 0 ] && [ "$failed_n" -gt 0 ]; then
    echo "updated $updated_n ($updated_list), $failed_n failed ($failed_list) of $count repos"
  elif [ "$updated_n" -gt 0 ]; then
    echo "updated $updated_n of $count repos ($updated_list)"
  elif [ "$failed_n" -gt 0 ]; then
    echo "$failed_n of $count repos failed ($failed_list)"
  else
    echo "all $count repos up to date"
  fi
  exit 0
fi

if ls "$TMP"/note.* >/dev/null 2>&1; then
  report=$(printf 'Developer folder sync: pulled %d repos (fast-forward only). Notable:\n%s' "$count" "$(cat "$TMP"/note.*)")
else
  report="Developer folder sync: all $count repos are up to date with GitHub and clean."
fi

emit_report "$report"
exit 0
