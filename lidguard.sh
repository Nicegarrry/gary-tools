#!/bin/bash
# lidguard — keep the Mac awake while Herdr agents are working.
#
# ALL SETTINGS LIVE IN settings.conf (same folder). You shouldn't need to edit this file.
#
# How it works, every few seconds:
#   1. Re-read settings.conf.
#   2. Ask Herdr whether any agent is "working" (or has just asked you a question — we wait
#      a few minutes for you to answer before giving up).
#   3. If yes, and no override applies (low battery, Low Power Mode, too hot, battery time
#      limit), turn on "pmset disablesleep" — the Mac won't sleep from the lid or from idling.
#   4. Otherwise turn it off. If we were holding a closed lid awake, put the Mac to sleep now
#      and post a notification saying why.
# Keep Awake mode (like caffeinate) keeps the Mac on regardless, optionally until a set time.

DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$DIR/settings.conf"
[ -f "$SETTINGS" ] || cp "$DIR/settings.default.conf" "$SETTINGS" 2>/dev/null
HERDR=$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")
JQ=$(command -v jq 2>/dev/null || echo /usr/bin/jq)
HELPER="$DIR/lidguard-helper"
LABEL="com.$(whoami).lidguard"   # launchd names (must match install.sh)
UID_NUM=$(id -u)

# ── Settings ────────────────────────────────────────────────────────────────

load_settings() {
  # Defaults, used if settings.conf is missing or a value is mistyped
  ENABLED=yes
  KEEP_AWAKE_ALWAYS=no
  KEEP_AWAKE_UNTIL=""
  MIN_BATTERY_PERCENT=20
  SLEEP_IN_LOW_POWER_MODE=yes
  HEAT_LIMIT=serious
  BATTERY_LID_CLOSED_LIMIT_HOURS=4
  WAIT_FOR_INPUT_MINUTES=3
  LOCK_SCREEN_WHEN_LID_CLOSES=yes
  LEAVE_ALONE_WITH_EXTERNAL_MONITOR=yes
  NOTIFY_ON_SLEEP=yes
  START_AT_LOGIN=yes
  TURN_ON_AT_LOGIN=no
  CHECK_EVERY_SECONDS=2
  WAIT_BEFORE_SLEEP_SECONDS=20

  # Read only NAME=value lines (never runs anything from the file)
  if [ -f "$SETTINGS" ]; then
    local key raw value
    while IFS='=' read -r key raw; do
      key=$(echo "$key" | tr -d '[:space:]')
      raw=$(echo "$raw" | sed 's/#.*//' | tr -d '[:space:]')
      value=$(echo "$raw" | tr '[:upper:]' '[:lower:]')
      case "$key" in
        ENABLED|KEEP_AWAKE_ALWAYS|SLEEP_IN_LOW_POWER_MODE|LEAVE_ALONE_WITH_EXTERNAL_MONITOR|\
        LOCK_SCREEN_WHEN_LID_CLOSES|NOTIFY_ON_SLEEP|START_AT_LOGIN|TURN_ON_AT_LOGIN)
          [[ "$value" =~ ^(yes|no)$ ]] && printf -v "$key" '%s' "$value" ;;
        MIN_BATTERY_PERCENT|CHECK_EVERY_SECONDS|WAIT_BEFORE_SLEEP_SECONDS|WAIT_FOR_INPUT_MINUTES)
          [[ "$value" =~ ^[0-9]+$ ]] && printf -v "$key" '%s' "$value" ;;
        BATTERY_LID_CLOSED_LIMIT_HOURS)
          [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] && printf -v "$key" '%s' "$value" ;;
        HEAT_LIMIT)
          [[ "$value" =~ ^(fair|serious|critical|off)$ ]] && HEAT_LIMIT=$value ;;
        KEEP_AWAKE_UNTIL)
          [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$ ]] && KEEP_AWAKE_UNTIL=$raw ;;
      esac
    done < <(grep -E '^[[:space:]]*[A-Z_]+[[:space:]]*=' "$SETTINGS")
  fi

  [ "$CHECK_EVERY_SECONDS" -lt 1 ] && CHECK_EVERY_SECONDS=1
  LIMIT_SECONDS=$(awk "BEGIN {printf \"%d\", $BATTERY_LID_CLOSED_LIMIT_HOURS * 3600}")
  case "$HEAT_LIMIT" in fair) HEAT_LEVEL=1 ;; serious) HEAT_LEVEL=2 ;; critical) HEAT_LEVEL=3 ;; *) HEAT_LEVEL=99 ;; esac
}

# Change one NAME=value line in settings.conf (used for timers and login reset)
set_setting() {
  if grep -qE "^$1=" "$SETTINGS"; then
    sed -i '' "s|^$1=.*|$1=$2|" "$SETTINGS"
  else
    echo "$1=$2" >> "$SETTINGS"
  fi
}

# ── Checks ──────────────────────────────────────────────────────────────────

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Prints "<working> <waiting-for-input>"
agent_counts() {
  local out
  out=$("$HERDR" agent list 2>/dev/null | "$JQ" -r '
    [.result.agents[]? | .agent_status] |
    "\(map(select(. == "working")) | length) \(map(select(. == "blocked")) | length)"' 2>/dev/null)
  echo "${out:-0 0}"
}

lid_closed() { ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'; }

on_power() { pmset -g batt | grep -q "AC Power"; }

battery_percent() { pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d %; }

low_power_mode() { pmset -g | grep -qE '^ *(powermode|lowpowermode) +1'; }

heat_level() { "$HELPER" thermal 2>/dev/null || echo 0; }

# True if any non-built-in display is connected
external_monitor() {
  local d total builtin
  d=$(system_profiler SPDisplaysDataType 2>/dev/null)
  total=$(echo "$d" | grep -c "Resolution:")
  builtin=$(echo "$d" | grep -c "Display Type: Built-in")
  [ "$total" -gt "$builtin" ]
}

# Identifies the current login session (changes every time you log in)
login_marker() {
  local pid
  pid=$(ps -axo pid=,user=,comm= | awk -v u="$(whoami)" '$2==u && $3 ~ /loginwindow$/ {print $1; exit}')
  [ -n "$pid" ] && echo "$pid $(ps -o lstart= -p "$pid")"
}

# "1h 23m" / "4m"
pretty_duration() {
  local s=$1 h m
  [ "$s" -lt 0 ] && s=0
  h=$((s / 3600)); m=$(((s % 3600 + 59) / 60))
  [ "$m" -eq 60 ] && { h=$((h + 1)); m=0; }
  if [ "$h" -gt 0 ]; then echo "${h}h ${m}m"; else echo "${m}m"; fi
}

# ── Actions ─────────────────────────────────────────────────────────────────

sleep_block_is_on() { [ "$(pmset -g | awk '/SleepDisabled/ {print $2}')" = "1" ]; }

block_sleep() { sleep_block_is_on || { sudo -n /usr/bin/pmset -a disablesleep 1 && log "sleep blocked"; }; }

allow_sleep() { sleep_block_is_on && { sudo -n /usr/bin/pmset -a disablesleep 0 && log "sleep allowed"; }; }

# One-line status read by the menu bar app: "<off|idle|awake|caffeine>|<message>"
write_status() { echo "$1|$2" > "$DIR/.status.tmp" && mv "$DIR/.status.tmp" "$DIR/.status"; }

lock_screen() { "$HELPER" lock && log "screen locked"; }

notify() {
  [ "$NOTIFY_ON_SLEEP" = yes ] || return
  osascript -e "display notification \"$1\" with title \"lidguard\"" >/dev/null 2>&1
}

# Put the Mac to sleep now, remember why, and don't re-hold it awake until the lid is opened
force_sleep() {
  stop_caffeinate
  allow_sleep
  log "going to sleep: $1"
  echo "$(date '+%a %H:%M')|$1" > "$DIR/.last_sleep"
  notify "Mac went to sleep: $1"
  slept_with_lid_closed=yes
  holding_closed_lid=no
  sleep 1
  pmset sleepnow >/dev/null
}

# Keep the display on too while in Keep Awake mode (a child caffeinate that dies with us)
start_caffeinate() {
  [ -n "$caff_pid" ] && kill -0 "$caff_pid" 2>/dev/null && return
  caffeinate -di -w $$ & caff_pid=$!
}
stop_caffeinate() { [ -n "$caff_pid" ] && kill "$caff_pid" 2>/dev/null; caff_pid=""; }

# Start-at-login: enable/disable both launchd jobs (affects next login, not what's running now)
apply_start_at_login() {
  [ "$START_AT_LOGIN" = "$applied_start_at_login" ] && return
  local verb=enable; [ "$START_AT_LOGIN" = no ] && verb=disable
  launchctl "$verb" "gui/$UID_NUM/$LABEL" 2>/dev/null
  launchctl "$verb" "gui/$UID_NUM/$LABEL.menubar" 2>/dev/null
  applied_start_at_login=$START_AT_LOGIN
  log "start at login: $START_AT_LOGIN"
}

# Note when we first hold a closed lid awake (and whether it's a desk setup with a monitor)
note_closed_lid() {
  [ "$lid" = closed ] && [ "$holding_closed_lid" = no ] || return 0
  if [ "$LEAVE_ALONE_WITH_EXTERNAL_MONITOR" = yes ] && external_monitor; then
    holding_closed_lid=monitor
  else
    holding_closed_lid=yes; log "lid closed — staying awake ($1)"
  fi
}

cleanup() { stop_caffeinate; allow_sleep; log "stopped"; exit 0; }
trap cleanup INT TERM

# ── Start-up ────────────────────────────────────────────────────────────────

holding_closed_lid=no     # yes while we're keeping a closed lid awake ("monitor" = desk setup)
slept_with_lid_closed=no  # yes after we forced sleep; cleared when the lid opens
idle_since=""             # when agents stopped being active
waiting_since=""          # when agents started waiting for your input
battery_closed_since=""   # when the current lid-closed-on-battery stretch began
hot_since=""              # when the Mac first got too hot (lid closed)
was_enabled=""
was_caffeine=""
caff_pid=""
applied_start_at_login=""
last_lid=$(lid_closed && echo closed || echo open)   # so we only lock on a fresh close

load_settings
log "started"

# Fresh login? Optionally start switched off.
marker=$(login_marker)
if [ -n "$marker" ] && [ "$marker" != "$(cat "$DIR/.login" 2>/dev/null)" ]; then
  if [ -f "$DIR/.login" ] && [ "$TURN_ON_AT_LOGIN" = no ]; then
    set_setting ENABLED no
    set_setting KEEP_AWAKE_ALWAYS no
    set_setting KEEP_AWAKE_UNTIL ""
    log "new login — starting switched off"
  fi
  echo "$marker" > "$DIR/.login"
fi

# ── Main loop ───────────────────────────────────────────────────────────────

while true; do
  load_settings
  apply_start_at_login
  now=$(date +%s)
  until_epoch=""

  # Lid, battery time limit and heat (timers only run while the lid is closed)
  if lid_closed; then
    lid=closed
    if on_power; then battery_closed_since=""
    elif [ -z "$battery_closed_since" ]; then battery_closed_since=$now; fi
    if [ "$(heat_level)" -ge "$HEAT_LEVEL" ]; then
      [ -z "$hot_since" ] && hot_since=$now
    else
      hot_since=""
    fi
  else
    lid=open; battery_closed_since=""; hot_since=""
    holding_closed_lid=no; slept_with_lid_closed=no
  fi
  too_hot=no
  [ -n "$hot_since" ] && [ $((now - hot_since)) -ge 60 ] && too_hot=yes   # sustained for a minute

  # Lock the screen the moment the lid closes (skip if a monitor is in use — you're working on it)
  if [ "$lid" = closed ] && [ "$last_lid" = open ] && [ "$LOCK_SCREEN_WHEN_LID_CLOSES" = yes ]; then
    external_monitor || lock_screen
  fi
  last_lid=$lid

  # After a forced sleep, stay out of the way until the lid is opened again
  # (stops the Mac re-waking itself in a bag and running hot again)
  if [ "$slept_with_lid_closed" = yes ]; then
    allow_sleep; stop_caffeinate
    write_status idle "Slept with lid closed — open the lid to resume"
    sleep "$CHECK_EVERY_SECONDS"; continue
  fi

  # ── Keep Awake mode (like caffeinate) ──
  if [ "$KEEP_AWAKE_ALWAYS" = yes ] && [ -n "$KEEP_AWAKE_UNTIL" ]; then
    until_epoch=$(date -j -f "%Y-%m-%dT%H:%M" "$KEEP_AWAKE_UNTIL" +%s 2>/dev/null)
    if [ -n "$until_epoch" ] && [ "$now" -ge "$until_epoch" ]; then
      set_setting KEEP_AWAKE_ALWAYS no
      set_setting KEEP_AWAKE_UNTIL ""
      KEEP_AWAKE_ALWAYS=no
      log "Keep Awake timer finished"
      notify "Keep Awake timer finished"
    fi
  fi

  if [ "$KEEP_AWAKE_ALWAYS" = yes ]; then
    [ "$was_caffeine" != yes ] && log "Keep Awake ON${KEEP_AWAKE_UNTIL:+ until $KEEP_AWAKE_UNTIL}"
    was_caffeine=yes
    if [ "$too_hot" = yes ] && [ "$holding_closed_lid" != monitor ]; then
      force_sleep "too hot with the lid closed"
      sleep "$CHECK_EVERY_SECONDS"; continue
    fi
    block_sleep
    start_caffeinate
    note_closed_lid "Keep Awake"
    if [ -n "$KEEP_AWAKE_UNTIL" ] && [ -n "$until_epoch" ]; then
      write_status caffeine "Keep Awake — $(pretty_duration $((until_epoch - now))) left"
    else
      write_status caffeine "Keep Awake — until you turn it off"
    fi
    sleep "$CHECK_EVERY_SECONDS"; continue
  fi
  if [ "$was_caffeine" = yes ]; then
    log "Keep Awake OFF"; was_caffeine=no; stop_caffeinate; idle_since=""
  fi

  # ── On/off switch ──
  if [ "$ENABLED" != "yes" ]; then
    [ "$was_enabled" != "no" ] && log "switched OFF"
    if [ "$holding_closed_lid" = yes ] && [ "$lid" = closed ]; then
      force_sleep "lidguard switched off with the lid closed"
    fi
    allow_sleep
    was_enabled=no; holding_closed_lid=no
    write_status off "Off — Mac sleeps normally"
    sleep "$CHECK_EVERY_SECONDS"; continue
  fi
  [ "$was_enabled" = "no" ] && log "switched ON"
  was_enabled=yes

  # ── Agents ──
  read -r working waiting <<< "$(agent_counts)"
  waiting_ok=no
  if [ "$working" -eq 0 ] && [ "$waiting" -gt 0 ]; then
    [ -z "$waiting_since" ] && { waiting_since=$now; log "agent waiting for input — holding ${WAIT_FOR_INPUT_MINUTES}m"; }
    [ $((now - waiting_since)) -lt $((WAIT_FOR_INPUT_MINUTES * 60)) ] && waiting_ok=yes
  else
    waiting_since=""
  fi
  active=no
  { [ "$working" -gt 0 ] || [ "$waiting_ok" = yes ]; } && active=yes

  # Reasons to let the Mac sleep
  reason=""
  if [ "$active" = no ]; then
    [ -z "$idle_since" ] && idle_since=$now
    if [ $((now - idle_since)) -ge "$WAIT_BEFORE_SLEEP_SECONDS" ]; then
      if [ "$waiting" -gt 0 ]; then reason="agent still waiting for your input"
      else reason="agents finished"; fi
    fi
  else
    idle_since=""
  fi
  if [ "$SLEEP_IN_LOW_POWER_MODE" = yes ] && low_power_mode; then reason="Low Power Mode is on"; fi
  if ! on_power; then
    pct=$(battery_percent)
    [ -n "$pct" ] && [ "$pct" -lt "$MIN_BATTERY_PERCENT" ] && reason="battery below ${MIN_BATTERY_PERCENT}%"
  fi
  if [ -n "$battery_closed_since" ] && [ $((now - battery_closed_since)) -ge "$LIMIT_SECONDS" ]; then
    reason="lid closed on battery for over ${BATTERY_LID_CLOSED_LIMIT_HOURS}h"
  fi
  if [ "$too_hot" = yes ] && [ "$holding_closed_lid" != monitor ]; then reason="too hot with the lid closed"; fi

  # Act
  if [ "$active" = yes ] && [ -z "$reason" ]; then
    block_sleep
    note_closed_lid "$working working, $waiting waiting"
  elif [ -n "$reason" ]; then
    if [ "$holding_closed_lid" = yes ] && [ "$lid" = closed ]; then
      force_sleep "$reason"
      sleep "$CHECK_EVERY_SECONDS"; continue
    fi
    allow_sleep
  fi

  # Status line for the menu bar app
  agents="$working agent"; [ "$working" -ne 1 ] && agents="${agents}s"
  if sleep_block_is_on; then
    if [ "$working" -gt 0 ]; then
      write_status awake "Keeping Mac awake — $agents working"
    else
      left=$((WAIT_FOR_INPUT_MINUTES * 60 - (now - ${waiting_since:-$now})))
      write_status awake "Waiting for your input — $(pretty_duration "$left") left"
    fi
  elif [ "$active" = yes ] && [ -n "$reason" ]; then
    write_status idle "Not keeping awake — $reason"
  elif [ "$active" = yes ]; then
    write_status idle "$agents working — about to keep awake"
  elif [ "$waiting" -gt 0 ]; then
    write_status idle "On — agent waiting for your input"
  else
    write_status idle "On — no agents working"
  fi

  sleep "$CHECK_EVERY_SECONDS"
done
