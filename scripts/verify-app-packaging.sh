#!/usr/bin/env bash
# Verify a built app without launching Tessera or querying a running app's socket.
set -euo pipefail
APP="${1:?Usage: bash scripts/verify-app-packaging.sh /path/to/Tessera.app}"
CONTENTS="$APP/Contents"
INFO="$CONTENTS/Info.plist"
CLI="$CONTENTS/Helpers/tessera"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "$CONTENTS/MacOS/Tessera" && -x "$CLI" ]] || fail "App or embedded CLI missing"
[[ -s "$CONTENTS/Resources/Tessera.sdef" && -s "$CONTENTS/Resources/Assets.car" ]] || fail "Bundle resources missing"
/usr/bin/plutil -lint "$INFO"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$INFO")" == com.prabeshbhetwal.Tessera ]] || fail "Wrong bundle identity"
[[ "$(/usr/libexec/PlistBuddy -c 'Print LSUIElement' "$INFO")" == true ]] || fail "Menu bar app flag missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleURLTypes:0:CFBundleURLSchemes:0' "$INFO")" == tessera ]] || fail "URL scheme missing"
/usr/bin/codesign --verify --deep --strict "$APP"

HELP="$("$CLI" --help)"
[[ "$HELP" == usage:* ]] || fail "CLI help missing"
if OUTPUT="$("$CLI" 2>&1)"; then fail "Empty CLI invocation succeeded"; else STATUS=$?; fi
[[ "$STATUS" -eq 2 && "$OUTPUT" == usage:* ]] || fail "Empty invocation must return usage exit 2"
if OUTPUT="$("$CLI" not-a-command 2>&1)"; then fail "Unknown CLI command succeeded"; else STATUS=$?; fi
[[ "$STATUS" -eq 2 && "$OUTPUT" == *"unknown command"* ]] || fail "Unknown command must return usage exit 2"
echo "PASS: Built app signature, resources, metadata and embedded CLI help/usage smoke."
