#!/bin/bash
# Gary Tools installer
#
# Usage:
#   ./install.sh                     Build and install (updates /Applications/Gary Tools.app if already installed there, else dist/)
#   ./install.sh --applications      Build and install atomically to /Applications/Gary Tools.app
#   ./install.sh --local-dist        Build and run directly from dist/Gary Tools.app
#   ./install.sh --no-sudo           Skip interactive pmset sudoers setup
#   ./install.sh --uninstall         Remove the background daemon (keeps user data)
#   ./install.sh --uninstall --remove-app  Also remove /Applications/Gary Tools.app
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_LABEL="com.$(whoami).garytools.daemon"
DAEMON_PLIST="$HOME/Library/LaunchAgents/$DAEMON_LABEL.plist"
OLD_LID_LABEL="com.$(whoami).lidguard"
OLD_MENU_LABEL="com.$(whoami).lidguard.menubar"
APP_BUNDLE_ID="local.nicegary.GaryTools"
BUILT_APP="$DIR/dist/Gary Tools.app"
APPLICATIONS_APP="/Applications/Gary Tools.app"
SUDOERS=/etc/sudoers.d/lidguard
LOG="$HOME/Library/Logs/gary-tools.log"
DATA_DIR="$HOME/Library/Application Support/Gary Tools"
GUI="gui/$(id -u)"

INSTALL_MODE=""
NO_SUDO=no
DO_UNINSTALL=no
REMOVE_APP=no

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --applications) INSTALL_MODE=applications ;;
    --local-dist)   INSTALL_MODE=local-dist ;;
    --no-sudo)      NO_SUDO=yes ;;
    --uninstall)    DO_UNINSTALL=yes ;;
    --remove-app)   REMOVE_APP=yes ;;
    -h|--help)      usage; exit 0 ;;
    *)              printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ "$(uname)" = Darwin ] || die "Gary Tools only runs on macOS."

bundle_id_of() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true
}

stop_job() {
  launchctl bootout "$GUI/$1" 2>/dev/null || true
  for _ in $(seq 1 40); do launchctl print "$GUI/$1" >/dev/null 2>&1 || return 0; sleep 0.2; done
}

stop_running_app() {
  pgrep -x GaryTools >/dev/null 2>&1 || return 0
  say "Quitting running Gary Tools so the new build can launch"
  osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 25); do
    pgrep -x GaryTools >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  pkill -TERM -x GaryTools 2>/dev/null || true
  for _ in $(seq 1 15); do
    pgrep -x GaryTools >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  warn "Previous GaryTools process did not exit cleanly; continuing anyway"
}

install_to_applications() {
  local src="$1"
  local dest="$APPLICATIONS_APP"
  local use_sudo=no

  if [ ! -w "/Applications" ] || { [ -e "$dest" ] && [ ! -w "$dest" ]; }; then
    if [ "$NO_SUDO" = no ] && [ -t 0 ]; then
      use_sudo=yes
    else
      die "Cannot write to /Applications without administrator privileges. Run interactively or install to dist/ with --local-dist."
    fi
  fi

  local staged="/Applications/.GaryTools.staging.$$.app"
  local backup="/Applications/.GaryTools.backup.$$.app"

  run_fs() {
    if [ "$use_sudo" = yes ]; then
      sudo "$@"
    else
      "$@"
    fi
  }

  cleanup_staging() {
    if [ -e "$staged" ]; then
      run_fs rm -rf "$staged" 2>/dev/null || true
    fi
  }
  trap cleanup_staging EXIT

  say "Installing Gary Tools.app to /Applications"
  run_fs rm -rf "$staged" "$backup"
  run_fs ditto "$src" "$staged"
  codesign --verify --strict "$staged"

  local had_existing=no
  if [ -e "$dest" ]; then
    had_existing=yes
    run_fs mv "$dest" "$backup"
  fi

  if ! run_fs mv "$staged" "$dest"; then
    if [ "$had_existing" = yes ] && [ -e "$backup" ]; then
      run_fs mv "$backup" "$dest" 2>/dev/null || true
    fi
    die "Failed to move staged app into $dest"
  fi

  if [ "$had_existing" = yes ] && [ -e "$backup" ]; then
    run_fs rm -rf "$backup" 2>/dev/null || true
  fi
  trap - EXIT
}

if [ "$DO_UNINSTALL" = yes ]; then
  say "Removing Gary Tools background daemon"
  stop_job "$DAEMON_LABEL"
  rm -f "$DAEMON_PLIST"

  say "Restoring normal sleep"
  if sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null; then
    :
  elif [ "$NO_SUDO" = no ] && [ -t 0 ]; then
    sudo /usr/bin/pmset -a disablesleep 0 || true
  else
    warn "Skipped pmset reset (non-interactive)."
  fi

  if [ "$REMOVE_APP" = yes ]; then
    stop_running_app
    if [ -d "$APPLICATIONS_APP" ]; then
      if [ "$(bundle_id_of "$APPLICATIONS_APP")" = "$APP_BUNDLE_ID" ]; then
        say "Removing $APPLICATIONS_APP"
        if [ -w "/Applications" ] && [ -w "$APPLICATIONS_APP" ]; then
          rm -rf "$APPLICATIONS_APP"
        elif [ "$NO_SUDO" = no ] && [ -t 0 ]; then
          sudo rm -rf "$APPLICATIONS_APP"
        else
          warn "Could not remove $APPLICATIONS_APP (insufficient permissions)."
        fi
      else
        warn "Skipped removing $APPLICATIONS_APP (bundle identifier does not match $APP_BUNDLE_ID)."
      fi
    fi
    [ -L "$HOME/.local/bin/dev-pull-all" ] && rm -f "$HOME/.local/bin/dev-pull-all"
    [ -L "$HOME/.local/bin/gary-tools-update" ] && rm -f "$HOME/.local/bin/gary-tools-update"
  fi

  echo "Gary Tools daemon removed. Your data remains in \"$DATA_DIR\"."
  exit 0
fi

# Resolve install destination
if [ -z "$INSTALL_MODE" ]; then
  if [ -d "$APPLICATIONS_APP" ] && [ "$(bundle_id_of "$APPLICATIONS_APP")" = "$APP_BUNDLE_ID" ]; then
    INSTALL_MODE=applications
  else
    INSTALL_MODE=local-dist
  fi
fi

if [ "$INSTALL_MODE" = applications ]; then
  INSTALLED_APP="$APPLICATIONS_APP"
else
  INSTALLED_APP="$BUILT_APP"
fi

# ── 1. Build first (leaves any running app intact if the build fails) ──
say "Building Gary Tools.app"
chmod +x "$DIR/build.sh" "$DIR/test.sh" "$DIR/update.sh" \
  "$DIR/scripts/lidguard.sh" "$DIR/scripts/dev-pull-all.sh" "$DIR/scripts/setup-signing.sh"
[ -f "$DIR/scripts/bootstrap.sh" ] && chmod +x "$DIR/scripts/bootstrap.sh"
"$DIR/build.sh"

# ── 2. Data dir, default config & recorded source checkout path ──
mkdir -p "$DATA_DIR" "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
if [ ! -f "$DATA_DIR/settings.conf" ]; then
  cp "$DIR/config/settings.default.conf" "$DATA_DIR/settings.conf"
  if [ ! -f "$DATA_DIR/Clipboard/library.json" ]; then
    : > "$DATA_DIR/.fresh_install"
  fi
fi
printf '%s\n' "$DIR" > "$DATA_DIR/source-repo.txt"
chmod 600 "$DATA_DIR/source-repo.txt"

# ── 3. sudo rule for pmset disablesleep ──
if ! sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null; then
  if [ "$NO_SUDO" = yes ] || [ ! -t 0 ]; then
    say "Skipped pmset sudo setup (non-interactive) — you can enable it in Gary Tools → Setup / Permissions."
  else
    say "Allowing Sleep Guard to toggle lid-close sleep (asks for your password once)"
    TMP=$(mktemp)
    echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TMP"
    sudo visudo -cf "$TMP" >/dev/null
    sudo install -m 0440 -o root -g wheel "$TMP" "$SUDOERS"
    rm -f "$TMP"
  fi
fi

# ── 4. Retire legacy lidguard LaunchAgents if present ──
stop_job "$OLD_MENU_LABEL"
stop_job "$OLD_LID_LABEL"
rm -f "$HOME/Library/LaunchAgents/$OLD_LID_LABEL.plist" "$HOME/Library/LaunchAgents/$OLD_MENU_LABEL.plist"

# ── 5. Quit running app, install bundle, symlink CLI helpers, restart daemon & app ──
stop_running_app

if [ "$INSTALL_MODE" = applications ]; then
  install_to_applications "$BUILT_APP"
fi

ln -sf "$INSTALLED_APP/Contents/Resources/dev-pull-all.sh" "$HOME/.local/bin/dev-pull-all"
ln -sf "$DIR/update.sh" "$HOME/.local/bin/gary-tools-update"

say "Starting Gary Tools background daemon"
cat > "$DAEMON_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$DAEMON_LABEL</string>
  <key>ProgramArguments</key><array><string>$INSTALLED_APP/Contents/Resources/lidguard.sh</string></array>
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

say "Opening $INSTALLED_APP"
open "$INSTALLED_APP"

# ── 6. Verify both processes came up ──
for _ in $(seq 1 15); do
  pgrep -x GaryTools >/dev/null 2>&1 && break
  sleep 0.2
done

APP_PID=$(pgrep -x GaryTools | head -1 || true)
DAEMON_PID=$(launchctl list | awk -v l="$DAEMON_LABEL" '$3 == l {print $1}' || true)
COMMIT=$(/usr/libexec/PlistBuddy -c "Print :GaryToolsGitCommit" "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")

if [ -n "$APP_PID" ]; then
  say "Gary Tools running (PID $APP_PID, daemon ${DAEMON_PID:-starting}, commit $COMMIT)"
else
  warn "Gary Tools was opened, but no running GaryTools process was detected yet."
fi
