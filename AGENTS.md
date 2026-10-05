# Tessera project guidance

- Native macOS 15 app: AppKit services and Core Animation overlays in `Tessera/`; pure Swift geometry, settings and input reducers in `Packages/TesseraCore/`.
- Product and visual conventions: `docs/PRODUCT.md` and `docs/DESIGN.md`. Use Australian English in visible copy; preserve command identifiers.
- Tessera is a clean-room implementation. `loop/` (main checkout only, gitignored) is upstream Loop under GPL-3.0: never read, search or copy its source. Behaviour notes live in `docs/loop-*.md`.
- Test: `swift test --package-path Packages/TesseraCore --scratch-path ~/Library/Caches/tessera-build/core-main`.
- Render Ring states and verify edge placement: `bash scripts/verify-ring-rendering.sh /tmp/tessera-ring-preview.png`. Choose a fresh output filename; this checks production layers without moving desktop windows.
- Build: `scripts/build-app.sh`. Set `TESSERA_DERIVED_DATA` to an isolated cache directory when verifying a change. XcodeGen generates the project from `project.yml`.
- Keep generated build products outside the checkout; signing can fail in synced folders. The build script uses the local signing identity when available.
- All input surfaces execute through `CommandBridge`. Keep selection geometry separate from presentation; changing the Ring's appearance must preserve configured gesture thresholds and wedge mappings.
- Overlay panels must remain non-activating and ignore mouse input. Reuse layers during cursor updates; respect Reduce Motion, theme colours and visibility switches.
- Ring presentation uses bare window-layout glyphs and a compact selected-action caption. Keep it free of outer segmented bands, individual tile backgrounds, repeated per-icon labels and centre cards. Preserve selection geometry during visual changes.
- New Swift files should remain below 300 lines. Avoid expanding existing oversized files when a focused presentation component suffices.
- Use CodeGraph when this checkout has an index; otherwise use targeted source reads. Use existing Graphify reports when present; do not assume a graph has been generated.
- Preserve existing files and user changes. Use focused patches; obtain confirmation before destructive overwrites, moves, renames or removals.
