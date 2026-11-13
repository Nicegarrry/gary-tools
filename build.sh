#!/bin/bash
# Builds the native parts: lidguard-helper (heat level + screen lock) and Lidguard.app (menu bar)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

swiftc -O -o "$DIR/lidguard-helper" "$DIR/helper.swift"
codesign --force --sign - "$DIR/lidguard-helper" >/dev/null 2>&1 || true
echo "built $DIR/lidguard-helper"

"$DIR/menubar/build.sh"
