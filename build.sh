#!/bin/bash
# Build Speak2Text.app (release), sign it and install into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="${S2T_IDENTITY:-Apple Development: Uladzislau Anisau (P3W3R69UM6)}"
APP=build/Speak2Text.app
DEST="$HOME/Applications/Speak2Text.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Speak2Text" "$APP/Contents/MacOS/Speak2Text"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${S2T_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $S2T_VERSION" -c "Set :CFBundleVersion ${S2T_BUILD:-$S2T_VERSION}" "$APP/Contents/Info.plist"
fi
for l in en ru; do mkdir -p "$APP/Contents/Resources/$l.lproj"; cp Resources/$l.lproj/InfoPlist.strings "$APP/Contents/Resources/$l.lproj/"; done
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || echo "note: Resources/AppIcon.icns not found, default icon"
cp Resources/MenuBarIcon*.png "$APP/Contents/Resources/" 2>/dev/null || echo "note: Resources/MenuBarIcon*.png not found, using SF Symbol waveform"
[ -f Resources/sample.wav ] && cp Resources/sample.wav "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/sounds"; cp Resources/sounds/*.wav "$APP/Contents/Resources/sounds/"

# Sparkle.framework (if the package provides it)
SPARKLE="$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' 2>/dev/null | head -1 || true)"
if [ -n "$SPARKLE" ]; then
    ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Speak2Text" 2>/dev/null || true
    FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    # sign nested code first, then the framework
    for x in "$FW"/XPCServices/*.xpc "$FW/Updater.app" "$FW/Autoupdate"; do
        [ -e "$x" ] && codesign -s "$IDENTITY" --force -o runtime "$x"
    done
    codesign -s "$IDENTITY" --force -o runtime "$APP/Contents/Frameworks/Sparkle.framework"
fi

codesign -s "$IDENTITY" --force --deep "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority=Apple Dev|Signature" || true

if [ -n "${S2T_NO_INSTALL:-}" ]; then echo "Built $PWD/$APP (not installed)"; exit 0; fi
mkdir -p "$HOME/Applications"
pkill -x Speak2Text 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Installed $DEST"
