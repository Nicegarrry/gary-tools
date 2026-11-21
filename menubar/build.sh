#!/bin/bash
# Build the menu-bar app with the shared CubeBit-style interface and flat icon.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../Lidguard.app"
CACHE="$HERE/.build"
mkdir -p "$CACHE/module-cache"
STAGE="$(mktemp -d "$CACHE/app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
BUILT_APP="$STAGE/Lidguard.app"
mkdir -p "$BUILT_APP/Contents/MacOS" "$BUILT_APP/Contents/Resources"

swiftc -O -module-cache-path "$CACHE/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" \
  -o "$BUILT_APP/Contents/MacOS/Lidguard" "$HERE/main.swift" "$HERE/Theme.swift"
swift -module-cache-path "$CACHE/module-cache" "$HERE/make-icon.swift" \
  "$CACHE/Lidguard.iconset" "$BUILT_APP/Contents/Resources/Lidguard.icns"

cat > "$BUILT_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lidguard</string>
  <key>CFBundleIdentifier</key><string>local.lidguard.menubar</string>
  <key>CFBundleExecutable</key><string>Lidguard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Lidguard</string>
  <key>CFBundleShortVersionString</key><string>1.1.1</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF
codesign --force --sign - "$BUILT_APP"
# Leave the last successful build in place if compilation or signing fails.
if [ -e "$APP" ]; then mv "$APP" "$STAGE/previous-Lidguard.app"; fi
if ! mv "$BUILT_APP" "$APP"; then
  if [ -e "$STAGE/previous-Lidguard.app" ]; then mv "$STAGE/previous-Lidguard.app" "$APP"; fi
  exit 1
fi
echo "built $APP"
