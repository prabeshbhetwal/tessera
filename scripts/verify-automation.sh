#!/usr/bin/env bash
# Exercise the production CLI socket with an isolated executor; never move desktop windows.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="${TESSERA_AUTOMATION_SCRATCH:-$HOME/Library/Caches/tessera-build/core-automation}"
xcrun swift build --target TesseraCore --jobs 2 --package-path Packages/TesseraCore --scratch-path "$SCRATCH"
PRODUCTS="$(xcrun swift build --show-bin-path --package-path Packages/TesseraCore --scratch-path "$SCRATCH")"
MODULES="$PRODUCTS"
if [[ -d "$PRODUCTS/Modules" ]]; then MODULES="$PRODUCTS/Modules"; fi
OBJECT="$(rg --files --hidden --no-ignore "$SCRATCH" | rg '/RingFeedback\.swift\.o$|/RingFeedback\.o$' | head -1)"
OBJECTS="$(dirname "$OBJECT")"
xcrun swiftc -parse-as-library -swift-version 6 -I "$MODULES" \
  Tessera/App/CommandBridge.swift Tessera/Automation/SocketServer.swift \
  scripts/verify-automation.swift "$OBJECTS"/*.o \
  -o "$SCRATCH/verify-automation"
"$SCRATCH/verify-automation"
