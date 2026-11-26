#!/bin/bash
# Gary Tools one-line bootstrap installer for macOS 14+
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh | bash
#
# Options:
#   --source-dir PATH   Where to clone/store the Gary Tools source checkout
#                       (default: ~/Library/Application Support/Gary Tools/source)
#   --branch BRANCH     Git branch to install (default: main)
#   --skip-signing      Skip creating a local trusted code signing certificate
#   --uninstall         Uninstall Gary Tools daemon (delegates to install.sh --uninstall)
#   --remove-app        With --uninstall, also remove /Applications/Gary Tools.app
#   -h, --help          Show this help
set -euo pipefail

REPO_URL="https://github.com/Nicegarrry/gary-tools.git"
DEFAULT_SOURCE_DIR="$HOME/Library/Application Support/Gary Tools/source"
BOOTSTRAP_CMD="curl -fsSL https://raw.githubusercontent.com/Nicegarrry/gary-tools/main/scripts/bootstrap.sh | bash"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Gary Tools bootstrap installer

Usage:
  $BOOTSTRAP_CMD
  bash bootstrap.sh [options]

Options:
  --source-dir PATH   Git checkout location (default: $DEFAULT_SOURCE_DIR)
  --branch BRANCH     Git branch to install (default: main)
  --skip-signing      Skip local trusted code signing certificate setup
  --uninstall         Remove the Gary Tools background daemon
  --remove-app        With --uninstall, also remove /Applications/Gary Tools.app
  -h, --help          Show this help
EOF
}

main() {
  local source_dir="$DEFAULT_SOURCE_DIR"
  local branch="main"
  local skip_signing=no
  local do_uninstall=no
  local remove_app=no

  while [ $# -gt 0 ]; do
    case "$1" in
      --source-dir)
        [ $# -ge 2 ] || die "--source-dir requires a path argument."
        source_dir="$2"
        shift 2
        ;;
      --branch)
        [ $# -ge 2 ] || die "--branch requires a branch name."
        branch="$2"
        shift 2
        ;;
      --skip-signing)
        skip_signing=yes
        shift
        ;;
      --uninstall)
        do_uninstall=yes
        shift
        ;;
      --remove-app)
        remove_app=yes
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  # Expand leading ~ if provided
  source_dir="${source_dir/#\~/$HOME}"
  source_dir="${source_dir%/}"

  # Verify macOS 14+
  [ "$(uname)" = Darwin ] || die "Gary Tools only runs on macOS."
  local macos_ver macos_major
  macos_ver=$(sw_vers -productVersion 2>/dev/null || echo "0")
  macos_major="${macos_ver%%.*}"
  if ! [[ "$macos_major" =~ ^[0-9]+$ ]] || [ "$macos_major" -lt 14 ]; then
    die "Gary Tools requires macOS 14 (Sonoma) or newer (detected macOS $macos_ver)."
  fi

  # Handle --uninstall cleanly
  if [ "$do_uninstall" = yes ]; then
    local uninstall_args=(--uninstall)
    [ "$remove_app" = yes ] && uninstall_args+=(--remove-app)

    if [ -f "$source_dir/install.sh" ]; then
      chmod +x "$source_dir/install.sh"
      "$source_dir/install.sh" "${uninstall_args[@]}"
    else
      warn "Source checkout not found at $source_dir; removing LaunchAgent directly."
      local daemon_label="com.$(whoami).garytools.daemon"
      local daemon_plist="$HOME/Library/LaunchAgents/$daemon_label.plist"
      local gui="gui/$(id -u)"
      launchctl bootout "$gui/$daemon_label" 2>/dev/null || true
      rm -f "$daemon_plist"
      sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || true
      if [ "$remove_app" = yes ] && [ -d "/Applications/Gary Tools.app" ]; then
        local bid
        bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "/Applications/Gary Tools.app/Contents/Info.plist" 2>/dev/null || true)
        if [ "$bid" = "local.nicegary.GaryTools" ]; then
          rm -rf "/Applications/Gary Tools.app"
          say "Removed /Applications/Gary Tools.app"
        fi
      fi
    fi

    echo ""
    echo "Uninstall guidance:"
    if [ -d "/Applications/Gary Tools.app" ]; then
      echo "  • To remove the app:          rm -rf \"/Applications/Gary Tools.app\""
    fi
    if [ -d "$source_dir" ]; then
      echo "  • To remove the source clone: rm -rf \"$source_dir\""
    fi
    echo "  • To remove all saved data:   rm -rf \"$HOME/Library/Application Support/Gary Tools\""
    exit 0
  fi

  # Check Xcode Command Line Tools (git + swift)
  local has_clt=yes
  if ! xcode-select -p >/dev/null 2>&1; then
    has_clt=no
  elif ! command -v git >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
    has_clt=no
  fi

  if [ "$has_clt" != yes ]; then
    say "Xcode Command Line Tools (git & swift) are required to build Gary Tools."
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "Apple's Command Line Tools installer has been opened (or is already running)."
    echo "Once the installation finishes, re-run this exact command:"
    echo ""
    echo "  $BOOTSTRAP_CMD"
    echo ""
    exit 1
  fi

  # Clone or fast-forward update the repository
  mkdir -p "$(dirname "$source_dir")"
  if [ -d "$source_dir/.git" ]; then
    if [ -n "$(git -C "$source_dir" status --porcelain 2>/dev/null)" ]; then
      warn "Local changes found in $source_dir — leaving working tree untouched (skipping git pull)."
    else
      say "Updating Gary Tools source in $source_dir ($branch)"
      git -C "$source_dir" fetch --prune origin
      local current_branch
      current_branch=$(git -C "$source_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
      if [ "$current_branch" != "$branch" ]; then
        if git -C "$source_dir" show-ref --verify --quiet "refs/heads/$branch"; then
          git -C "$source_dir" checkout "$branch"
        else
          git -C "$source_dir" checkout -b "$branch" "origin/$branch"
        fi
      fi
      if ! git -C "$source_dir" merge --ff-only "origin/$branch"; then
        warn "Could not fast-forward $branch cleanly; continuing with current checkout."
      fi
    fi
  elif [ -e "$source_dir" ] && [ -n "$(ls -A "$source_dir" 2>/dev/null || true)" ]; then
    die "$source_dir already exists and is not a git repository. Re-run with --source-dir PATH."
  else
    say "Cloning Gary Tools ($branch) into $source_dir"
    git clone --branch "$branch" "$REPO_URL" "$source_dir"
  fi

  # Create local trusted signing certificate so macOS permissions persist across updates
  if [ "$skip_signing" = no ]; then
    say "Setting up local code signing certificate (preserves Accessibility & Screen Recording permissions across updates)"
    chmod +x "$source_dir/scripts/setup-signing.sh"
    if ! "$source_dir/scripts/setup-signing.sh"; then
      warn "Local code signing setup did not complete — continuing with ad-hoc signing."
      warn "You can run \"$source_dir/scripts/setup-signing.sh\" later so permissions survive future updates."
    fi
  else
    say "Skipping local code signing setup (--skip-signing)"
  fi

  # Build, install to /Applications/Gary Tools.app, configure daemon, and open Setup Wizard
  chmod +x "$source_dir/install.sh"
  "$source_dir/install.sh" --applications

  echo ""
  say "Gary Tools is installed in /Applications/Gary Tools.app!"
  echo "Follow the Setup Wizard to grant permissions and choose your features."
  echo "Future updates can be installed from inside Gary Tools or by running: gary-tools-update"
}

main "$@"
