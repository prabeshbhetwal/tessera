#!/usr/bin/env bash
# Generate the Xcode project, build Tessera, sign it, print the .app path.
# Build output lives outside the repo: the repo may sit in iCloud Drive, which breaks codesign.
#
# Signing: uses the local "Tessera Local Signing" identity when the login keychain has it, so macOS
# keeps the Accessibility grant across rebuilds (stable designated requirement). Falls back to
# ad-hoc ("-") everywhere else, e.g. CI. Override with TESSERA_SIGN_IDENTITY.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED="${TESSERA_DERIVED_DATA:-$HOME/Library/Caches/tessera-build/dd-main}"
CONFIG="${CONFIGURATION:-Debug}"
LOCAL_ID="Tessera Local Signing"

if [[ -n "${TESSERA_SIGN_IDENTITY:-}" ]]; then
  SIGN_ID="$TESSERA_SIGN_IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -q "\"$LOCAL_ID\""; then
  SIGN_ID="$LOCAL_ID"
else
  SIGN_ID="-"
fi

xcodegen generate --quiet
# A build number that always increases, so macOS launches this build rather than an older copy with the
# same bundle ID (it picks the highest CFBundleVersion).
BUILD_NUMBER="$(date -u +%Y%m%d.%H%M%S)"
xcodebuild -project Tessera.xcodeproj -scheme Tessera -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" build -quiet CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

APP="$DERIVED/Build/Products/$CONFIG/Tessera.app"
# --deep: re-signs nested code (embedded CLI, debug dylib) with the same identity.
codesign --force --deep -s "$SIGN_ID" "$APP"
# Tell LaunchServices about this copy now, so a launch by bundle ID finds it straight away.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "$APP"
