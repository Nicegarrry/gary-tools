#!/bin/zsh
# Builds Gary Tools.app (SwiftPM release + lidguard-helper + CubeBit AppIcon + code sign).
set -euo pipefail
cd "${0:A:h}"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/dist"

# Resolve signing identity: explicit env override > local self-signed cert > ad-hoc fallback
DEFAULT_CERT="Gary Tools Local Signing"
SIGN_ID="${GARY_TOOLS_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$DEFAULT_CERT\""; then
    SIGN_ID="$DEFAULT_CERT"
  else
    SIGN_ID="-"
  fi
fi

# 1. Generate CubeBit Gary Tools icon
xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$PWD/Resources/AppIcon.icns"

# 2. Build native thermal/lock helper
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -o "$PWD/.build/lidguard-helper" "$PWD/scripts/helper.swift"
codesign --force --sign "$SIGN_ID" "$PWD/.build/lidguard-helper" >/dev/null 2>&1 || true

# 3. Build GaryTools Swift package
swift build -c release -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/cache"

# 4. Stage bundle atomically so a running copy keeps its mapped binary intact
APP="$PWD/dist/Gary Tools.app"
STAGED="$PWD/.build/GaryTools.staging.$$.app"
trap 'rm -rf "$STAGED"' EXIT
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources"

cp "$PWD/.build/release/GaryTools" "$STAGED/Contents/MacOS/GaryTools"
cp "$PWD/Resources/Info.plist" "$STAGED/Contents/Info.plist"
cp "$PWD/Resources/AppIcon.icns" "$STAGED/Contents/Resources/AppIcon.icns"
cp "$PWD/.build/lidguard-helper" "$STAGED/Contents/Resources/lidguard-helper"
cp "$PWD/scripts/lidguard.sh" "$STAGED/Contents/Resources/lidguard.sh"
cp "$PWD/scripts/dev-pull-all.sh" "$STAGED/Contents/Resources/dev-pull-all.sh"
cp "$PWD/config/settings.default.conf" "$STAGED/Contents/Resources/settings.default.conf"
chmod +x "$STAGED/Contents/Resources/lidguard.sh" "$STAGED/Contents/Resources/dev-pull-all.sh" "$STAGED/Contents/Resources/lidguard-helper"

# Stamp build number and commit into the staged Info.plist (never touches git-tracked Resources/Info.plist)
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
  GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$STAGED/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Delete :GaryToolsGitCommit" "$STAGED/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :GaryToolsGitCommit string $GIT_SHA" "$STAGED/Contents/Info.plist" >/dev/null 2>&1 || true
fi

codesign --force --sign "$SIGN_ID" --identifier local.nicegary.GaryTools "$STAGED"
codesign --verify --strict "$STAGED"

if [[ -d "$APP" ]]; then
  mkdir -p "$PWD/.build/previous-apps"
  BACKUP="$(mktemp -d "$PWD/.build/previous-apps/backup.XXXXXX")"
  mv "$APP" "$BACKUP/Gary Tools.app"
  # Keep only the 3 most recent backups
  ls -1dt "$PWD/.build/previous-apps"/backup.* 2>/dev/null | tail -n +4 | xargs -I{} rm -rf "{}" 2>/dev/null || true
fi
mv "$STAGED" "$APP"
print "Built: $APP"
if [[ "$SIGN_ID" == "-" ]]; then
  print "Signed: ad-hoc (run ./scripts/setup-signing.sh once so macOS Accessibility permissions persist across rebuilds)"
else
  print "Signed: $SIGN_ID"
fi
