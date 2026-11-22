#!/bin/zsh
# Builds Gary Tools.app (SwiftPM release + lidguard-helper + CubeBit AppIcon + ad-hoc sign).
set -euo pipefail
cd "${0:A:h}"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/dist"

# 1. Generate CubeBit Gary Tools icon
xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$PWD/Resources/AppIcon.icns"

# 2. Build native thermal/lock helper
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -o "$PWD/.build/lidguard-helper" "$PWD/scripts/helper.swift"
codesign --force --sign - "$PWD/.build/lidguard-helper" >/dev/null 2>&1 || true

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

codesign --force --sign - --identifier local.nicegary.GaryTools "$STAGED"
codesign --verify --strict "$STAGED"

if [[ -d "$APP" ]]; then
  mkdir -p "$PWD/.build/previous-apps"
  BACKUP="$(mktemp -d "$PWD/.build/previous-apps/backup.XXXXXX")"
  mv "$APP" "$BACKUP/Gary Tools.app"
fi
mv "$STAGED" "$APP"
print "Built: $APP"
