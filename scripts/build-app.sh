#!/usr/bin/env bash
# Generate the Xcode project, build Tessera, ad-hoc sign it, print the .app path.
# Build output lives outside the repo: the repo may sit in iCloud Drive, which breaks codesign.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED="${TESSERA_DERIVED_DATA:-$HOME/Library/Caches/tessera-build/dd-main}"
CONFIG="${CONFIGURATION:-Debug}"

xcodegen generate --quiet
xcodebuild -project Tessera.xcodeproj -scheme Tessera -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" build -quiet

APP="$DERIVED/Build/Products/$CONFIG/Tessera.app"
codesign --force --deep -s - "$APP"
echo "$APP"
