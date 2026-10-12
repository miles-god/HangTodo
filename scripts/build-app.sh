#!/bin/bash
# Build an Apple silicon HangTodo.app. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/HangTodo.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift build -c "$CONFIG" --triple arm64-apple-macosx14.0
cp "$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)/HangTodo" "$WORK/HangTodo"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/HangTodo" "$APP/Contents/MacOS/HangTodo"

swift scripts/make-todo-icon.swift "$WORK/icon.png"
ICONSET="$WORK/HangTodo.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z "$((SIZE*2))" "$((SIZE*2))" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/HangTodo.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>HangTodo</string>
  <key>CFBundleDisplayName</key><string>HangTodo</string>
  <key>CFBundleIdentifier</key><string>app.hangtodo.HangTodo</string>
  <key>CFBundleExecutable</key><string>HangTodo</string>
  <key>CFBundleIconFile</key><string>HangTodo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
