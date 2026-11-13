#!/usr/bin/env bash
# Verify the identity that preserves Accessibility grants, rather than only the certificate's display name.
set -euo pipefail
APP="${1:?Usage: verify-release-signature.sh /path/to/Tessera.app}"
REQUIREMENT='identifier "com.prabeshbhetwal.Tessera" and certificate leaf = H"b43488046b7b4372b6dff39afd2712f6dd665dbd"'
/usr/bin/codesign --verify --deep --strict -R "=$REQUIREMENT" "$APP"
