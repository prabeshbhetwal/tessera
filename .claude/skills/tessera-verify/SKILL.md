---
name: tessera-verify
description: Verify a Tessera change before committing — core tests, a signed app build, and a Ring render when Ring drawing changed — on per-branch caches so parallel worktrees never share build state. Use this instead of the generic /verify in this repo, and before every commit that touches Swift.
---

# Verify a Tessera change

Run from the checkout being verified. Bash calls don't share shell variables, so every command below starts with the same branch line. Steps 2 to 4 need the Bash sandbox off: SwiftPM nests its own sandbox, and xcodebuild and codesign write outside the repo.

1. **Scope.** List what changed against `main`, committed and uncommitted:

   ```bash
   git diff --name-only "$(git merge-base HEAD origin/main)"; git status --short
   ```

   Docs-only or `.claude/`-only changes need no build: report "skipped (no Swift changes)" and stop.

2. **Core tests** (Swift Testing; the XCTest "Executed 0 tests" line is noise):

   ```bash
   B=$(git branch --show-current | tr '/' '-'); B=${B:-$(git rev-parse --short HEAD)}
   swift test --package-path Packages/TesseraCore --scratch-path "$HOME/Library/Caches/tessera-build/core-$B"
   ```

3. **App build** (XcodeGen, xcodebuild, signing; prints the `.app` path):

   ```bash
   B=$(git branch --show-current | tr '/' '-'); B=${B:-$(git rev-parse --short HEAD)}
   TESSERA_DERIVED_DATA="$HOME/Library/Caches/tessera-build/dd-$B" scripts/build-app.sh
   ```

   From a Claude session the signing identity is usually not visible, so the build comes out ad-hoc signed and macOS asks for Accessibility again. That is expected, not a failure.

4. **Ring render**, only when step 1 lists a path matching `*Ring*`, `Tessera/Overlay/HexColor.swift` or `scripts/verify-ring-rendering*`:

   ```bash
   B=$(git branch --show-current | tr '/' '-'); B=${B:-$(git rev-parse --short HEAD)}
   TESSERA_RING_SCRATCH="$HOME/Library/Caches/tessera-build/ring-$B" \
     bash scripts/verify-ring-rendering.sh "${TMPDIR:-/tmp}/tessera-ring-$B-$(date +%Y%m%d-%H%M%S).png"
   ```

   Read the PNG and check it against the Ring rules in AGENTS.md: bare glyphs, one compact caption, no bands, tile backgrounds, per-icon labels or centre cards.

5. **Report** one line per step: passed (with the test count), failed (with the first error), or skipped (and why).

Stop at the first failure. Never commit on a failed step.
