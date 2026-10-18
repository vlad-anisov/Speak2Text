#!/bin/bash
# Usage: scripts/release.sh <version>
# Builds a signed Speak2Text.app, zips it and creates a Sparkle appcast in dist/.
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
echo
echo "Done: $ZIP and dist/appcast.xml (nothing was published)."
echo "Release tag: v$VERSION. appcast.xml must be attached to the release (feed: releases/latest/download/appcast.xml)."
