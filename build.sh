#!/bin/bash
# Rebuild release binary and wrap it into Dictate.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=Dictate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/dictate "$APP/Contents/MacOS/dictate"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.vlad.dictate</string>
    <key>CFBundleName</key><string>Dictate</string>
    <key>CFBundleDisplayName</key><string>Dictate</string>
    <key>CFBundleExecutable</key><string>dictate</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Dictate records your voice while the hotkey is held and recognizes it locally.</string>
</dict>
</plist>
PLIST
codesign -s "Apple Development: Uladzislau Anisau (P3W3R69UM6)" --force --deep "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
echo "Built $PWD/$APP"
