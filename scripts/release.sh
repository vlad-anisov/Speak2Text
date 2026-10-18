#!/bin/bash
# Usage: scripts/release.sh <version>
# Builds a signed Speak2Text.app, zips it, builds a drag-to-Applications .dmg and creates a Sparkle appcast in dist/.
# Publishes nothing: upload dist/Speak2Text-<version>.zip and dist/appcast.xml to a GitHub release yourself.
# The EdDSA private key is read from the login Keychain (created once with Sparkle's generate_keys).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version>}"
GEN=.build/artifacts/sparkle/Sparkle/bin/generate_appcast

S2T_VERSION="$VERSION" S2T_BUILD="${S2T_BUILD:-$(date +%Y%m%d%H%M)}" S2T_NO_INSTALL=1 ./build.sh
[ -x "$GEN" ] || { echo "generate_appcast not found, run 'swift build' first"; exit 1; }

mkdir -p dist
ZIP="dist/Speak2Text-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Speak2Text.app "$ZIP"

"$GEN" --download-url-prefix "https://github.com/vlad-anisov/Speak2Text/releases/download/v$VERSION/" dist
# DMG for people (built after the appcast so generate_appcast does not see two archives of one version): app on the left, arrow, Applications on the right (dmgbuild in a venv under .build, no Finder scripting)
DMG="dist/Speak2Text-$VERSION.dmg"
VENV=.build/dmgvenv
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }
swift scripts/make_dmg_background.swift build/dmg-bg
tiffutil -cathidpicheck build/dmg-bg/background.png build/dmg-bg/background@2x.png -out build/dmg-bg/background.tiff
rm -f "$DMG"
S2T_APP="$PWD/build/Speak2Text.app" S2T_DMG_BG="$PWD/build/dmg-bg/background.tiff" \
    "$VENV/bin/dmgbuild" -s scripts/dmg_settings.py "Speak2Text" "$DMG"
codesign -s "${S2T_IDENTITY:-Apple Development: Uladzislau Anisau (P3W3R69UM6)}" --force "$DMG"

echo
echo "Done: $DMG (for people), $ZIP (for Sparkle) and dist/appcast.xml (nothing was published)."
echo "Release tag: v$VERSION. appcast.xml must be attached to the release (feed: releases/latest/download/appcast.xml)."
