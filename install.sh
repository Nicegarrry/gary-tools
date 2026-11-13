#!/bin/bash
# lidguard installer
#
#   Install / update:  curl -fsSL https://raw.githubusercontent.com/Nicegarrry/lidguard/main/install.sh | bash
#   Uninstall:         ~/.lidguard/install.sh --uninstall
#
# What it sets up:
#   1. A sudo rule allowing ONLY `pmset -a disablesleep 0|1` without a password
#      (that's the switch that stops a closed lid from sleeping the Mac).
#   2. A LaunchAgent running lidguard.sh in the background.
#   3. A LaunchAgent for the menu bar app.
set -euo pipefail

REPO_URL="https://github.com/Nicegarrry/lidguard.git"
INSTALL_DIR="${LIDGUARD_DIR:-$HOME/.lidguard}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = Darwin ] || die "lidguard only runs on macOS."

# ── Piped from curl? Fetch the repo, then run the real installer from it ──
SRC="${BASH_SOURCE[0]:-}"
if [ -z "$SRC" ] || [ ! -f "$(dirname "$SRC")/lidguard.sh" ]; then
  command -v git >/dev/null || die "git not found. Install Apple's command line tools first:  xcode-select --install"
  if [ -d "$INSTALL_DIR/.git" ]; then
    say "Updating $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only --quiet
  else
    say "Downloading lidguard to $INSTALL_DIR"
    git clone --quiet --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
  exec bash "$INSTALL_DIR/install.sh" "$@" < /dev/tty
fi

DIR="$(cd "$(dirname "$SRC")" && pwd)"
LABEL="com.$(whoami).lidguard"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MENU_LABEL="$LABEL.menubar"
MENU_PLIST="$HOME/Library/LaunchAgents/$MENU_LABEL.plist"
SUDOERS=/etc/sudoers.d/lidguard
LOG="$HOME/Library/Logs/lidguard.log"
GUI="gui/$(id -u)"

# Stop a launchd job and wait until it has really gone (bootout is asynchronous)
stop_job() {
  launchctl bootout "$GUI/$1" 2>/dev/null || true
  for _ in $(seq 1 50); do launchctl print "$GUI/$1" >/dev/null 2>&1 || return 0; sleep 0.2; done
}

# ── Uninstall ──
if [ "${1:-}" = "--uninstall" ]; then
  say "Removing lidguard"
  stop_job "$MENU_LABEL"
  stop_job "$LABEL"
  launchctl enable "$GUI/$LABEL" 2>/dev/null || true
  launchctl enable "$GUI/$MENU_LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$MENU_PLIST"
  say "Restoring normal sleep (may ask for your password)"
  sudo /usr/bin/pmset -a disablesleep 0
  sudo rm -f "$SUDOERS"
  echo
  echo "lidguard removed. You can delete the folder too:  rm -rf \"$DIR\""
  exit 0
fi

# ── Prerequisites ──
command -v swiftc >/dev/null || die "Swift compiler not found. Install Apple's command line tools:  xcode-select --install"
command -v jq >/dev/null || die "jq not found (it ships with macOS 15+). Install it with:  brew install jq"
if ! command -v herdr >/dev/null && [ ! -x "$HOME/.local/bin/herdr" ]; then
  warn "Herdr not found. lidguard watches Herdr agents (https://herdr.dev) — Keep Awake works without it."
fi

# ── Build ──
say "Building (takes ~30 seconds the first time)"
chmod +x "$DIR/lidguard.sh" "$DIR/build.sh" "$DIR/menubar/build.sh"
"$DIR/build.sh" >/dev/null
[ -f "$DIR/settings.conf" ] || cp "$DIR/settings.default.conf" "$DIR/settings.conf"

# ── 1. sudo rule (only for toggling disablesleep) ──
if ! sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null; then
  say "Allowing lidguard to toggle lid-close sleep (asks for your password once)"
  TMP=$(mktemp)
  echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TMP"
  sudo visudo -cf "$TMP" >/dev/null
  sudo install -m 0440 -o root -g wheel "$TMP" "$SUDOERS"
  rm -f "$TMP"
fi

# ── 2. Background service ──
say "Starting lidguard"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/lidguard.sh</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
stop_job "$LABEL"
launchctl enable "$GUI/$LABEL"
launchctl bootstrap "$GUI" "$PLIST"

# ── 3. Menu bar app ──
cat > "$MENU_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$MENU_LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/Lidguard.app/Contents/MacOS/Lidguard</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
stop_job "$MENU_LABEL"
launchctl enable "$GUI/$MENU_LABEL"
launchctl bootstrap "$GUI" "$MENU_PLIST"

echo
say "lidguard is running — look for the cup in your menu bar."
echo "    Click: on/off · Option-click: Keep Awake · Right-click: menu & Settings"
echo "    Log: $LOG"
echo "    Uninstall: \"$DIR/install.sh\" --uninstall"
