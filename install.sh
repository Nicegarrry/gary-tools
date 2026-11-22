#!/bin/bash
# Gary Tools installer
#
#   Install / update:  ./install.sh
#   Uninstall:         ./install.sh --uninstall
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_LABEL="com.$(whoami).garytools.daemon"
DAEMON_PLIST="$HOME/Library/LaunchAgents/$DAEMON_LABEL.plist"
OLD_LID_LABEL="com.$(whoami).lidguard"
OLD_MENU_LABEL="com.$(whoami).lidguard.menubar"
SUDOERS=/etc/sudoers.d/lidguard
LOG="$HOME/Library/Logs/gary-tools.log"
DATA_DIR="$HOME/Library/Application Support/Gary Tools"
GUI="gui/$(id -u)"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = Darwin ] || die "Gary Tools only runs on macOS."

stop_job() {
  launchctl bootout "$GUI/$1" 2>/dev/null || true
  for _ in $(seq 1 40); do launchctl print "$GUI/$1" >/dev/null 2>&1 || return 0; sleep 0.2; done
}

if [ "${1:-}" = "--uninstall" ]; then
  say "Removing Gary Tools background daemon"
  stop_job "$DAEMON_LABEL"
  rm -f "$DAEMON_PLIST"
  say "Restoring normal sleep"
  sudo /usr/bin/pmset -a disablesleep 0 || true
  echo "Gary Tools daemon removed. Your data remains in \"$DATA_DIR\"."
  exit 0
fi

# ── 1. Build ──
say "Building Gary Tools.app"
chmod +x "$DIR/build.sh" "$DIR/test.sh" "$DIR/scripts/lidguard.sh" "$DIR/scripts/dev-pull-all.sh"
"$DIR/build.sh"

# ── 2. Data dir & default config ──
mkdir -p "$DATA_DIR" "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
[ -f "$DATA_DIR/settings.conf" ] || cp "$DIR/config/settings.default.conf" "$DATA_DIR/settings.conf"
ln -sf "$DIR/scripts/dev-pull-all.sh" "$HOME/.local/bin/dev-pull-all"

# ── 3. sudo rule for pmset disablesleep ──
if ! sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null; then
  say "Allowing Sleep Guard to toggle lid-close sleep (asks for your password once)"
  TMP=$(mktemp)
  echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TMP"
  sudo visudo -cf "$TMP" >/dev/null
  sudo install -m 0440 -o root -g wheel "$TMP" "$SUDOERS"
  rm -f "$TMP"
fi

# ── 4. Retire legacy lidguard LaunchAgents if present ──
stop_job "$OLD_MENU_LABEL"
stop_job "$OLD_LID_LABEL"
rm -f "$HOME/Library/LaunchAgents/$OLD_LID_LABEL.plist" "$HOME/Library/LaunchAgents/$OLD_MENU_LABEL.plist"

# ── 5. Install Gary Tools background daemon LaunchAgent ──
say "Starting Gary Tools background daemon"
cat > "$DAEMON_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$DAEMON_LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/dist/Gary Tools.app/Contents/Resources/lidguard.sh</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin</string>
    <key>GARY_TOOLS_DATA_DIR</key><string>$DATA_DIR</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
stop_job "$DAEMON_LABEL"
launchctl enable "$GUI/$DAEMON_LABEL"
launchctl bootstrap "$GUI" "$DAEMON_PLIST"

say "Gary Tools installed — opening app"
open "$DIR/dist/Gary Tools.app"
