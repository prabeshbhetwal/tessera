#!/usr/bin/env bash
# Render production Ring layers without Accessibility or desktop window changes.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="${TESSERA_RING_SCRATCH:-$HOME/Library/Caches/tessera-build/core-ring-rendering}"
OUTPUT="${1:-/tmp/tessera-ring-$(date +%Y%m%d-%H%M%S).png}"
if [[ -e "$OUTPUT" ]]; then
  echo "Output already exists; choose a new filename: $OUTPUT" >&2
  exit 1
fi
xcrun swift build --target TesseraCore --package-path Packages/TesseraCore --scratch-path "$SCRATCH"
PRODUCTS="$(xcrun swift build --show-bin-path --package-path Packages/TesseraCore --scratch-path "$SCRATCH")"
MODULES="$PRODUCTS"
if [[ -d "$PRODUCTS/Modules" ]]; then MODULES="$PRODUCTS/Modules"; fi
OBJECT="$(rg --files --hidden --no-ignore "$SCRATCH" | rg '/RingFeedback\.swift\.o$|/RingFeedback\.o$' | head -1)"
OBJECTS="$(dirname "$OBJECT")"
xcrun swiftc -parse-as-library -swift-version 6 -I "$MODULES" \
  Tessera/Overlay/HexColor.swift Tessera/Overlay/RingLayer.swift \
  Tessera/Overlay/RingGeometry.swift Tessera/Overlay/RingHubLayer.swift \
  Tessera/Overlay/RingCaptionLayer.swift scripts/verify-ring-rendering.swift \
  "$OBJECTS"/*.o -o "$SCRATCH/verify-ring-rendering"
"$SCRATCH/verify-ring-rendering" "$OUTPUT"
