#!/bin/bash
# Usage: scripts/release.sh <version>
# Builds a signed Speak2Text.app, zips it, builds a drag-to-Applications .dmg and creates a Sparkle appcast in dist/.
# Publishes nothing: upload dist/Speak2Text-<version>.dmg, dist/Speak2Text.dmg, dist/Speak2Text-<version>.zip, the .delta files and dist/appcast.xml to a GitHub release yourself.
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

# dmgs are not Sparkle archives: set them aside so generate_appcast sees only the zips
STASH=build/dmg-stash; rm -rf "$STASH"; mkdir -p "$STASH"
mv dist/*.dmg "$STASH"/ 2>/dev/null || true
"$GEN" --download-url-prefix "https://github.com/vlad-anisov/Speak2Text/releases/download/v$VERSION/" dist
mv "$STASH"/*.dmg dist/ 2>/dev/null || true
# generate_appcast uses one prefix for every item: point each item (zip and deltas) to the release tag of its own version
python3 - dist/appcast.xml <<'PY'
import re, sys
p = sys.argv[1]
xml = open(p).read()
def fix(m):
    item = m.group(0)
    v = re.search(r"<sparkle:shortVersionString>([^<]+)<", item).group(1)
    return re.sub(r"/releases/download/v[^/]+/", "/releases/download/v%s/" % v, item)
open(p, "w").write(re.sub(r"<item>.*?</item>", fix, xml, flags=re.S))
PY
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
# unversioned copy: https://github.com/vlad-anisov/Speak2Text/releases/latest/download/Speak2Text.dmg always points to the newest release
cp -f "$DMG" dist/Speak2Text.dmg

echo
echo "Done: $DMG and dist/Speak2Text.dmg (for people), $ZIP (for Sparkle) and dist/appcast.xml (nothing was published)."
echo "Release tag: v$VERSION. appcast.xml must be attached to the release (feed: releases/latest/download/appcast.xml)."
