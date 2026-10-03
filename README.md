# Tessera

A macOS window manager that adapts to every display.

Hold a trigger key, then **flick** or **point** to snap the frontmost window:

- **Flick:** a short flick picks a wedge from the ring (halves, quarters, maximize, center).
- **Point:** move further and point at a column. Each display gets its own grid, sized from its usable resolution. A 14" MacBook gets halves and quarters. A 49" 32:9 ultrawide gets 5 columns by default.
  - **Scroll** while holding to change the column count. Tessera remembers it per monitor.
  - **Click** while holding to span a window across several columns.

The preview shows:
- a live thumbnail of the window in its new spot
- the exact size and slot
- dimming on the windows it will cover
- an outline of where the window was

Everything is customisable. Settings export and import as one JSON file.

## Keyboard-only use

Everything works without a mouse.

**The ring.** While you hold the trigger, these keys control it:

| Key | Action |
|---|---|
| ← / → | Move one column |
| ⇧← / ⇧→ | Extend the span |
| ↑ / ↓ | Bottom, full or top band |
| 1–9 | Jump to that column |
| = / − | Change the column count |
| Tab / ⇧Tab | Next / previous display |
| Return | Apply |
| Esc | Cancel |

**Hotkeys.** These work without the ring, and you can rebind all of them in Settings → Shortcuts:

| Key | Action |
|---|---|
| ⌃⌥← / ⌃⌥→ | Cycle: half, edge column, two columns |
| ⌃⌥↑ | Maximize |
| ⌃⌥↓ | Center |
| ⌃⌥1–9 | Column N |
| ⌃⌥= / ⌃⌥− | Columns ±1 |
| ⌃⌥N / ⌃⌥P | Next / previous display |
| ⌃⌥Z | Undo |
| ⌃⌥⌘, | Settings |

**Settings window.** ⌘1–8 switches panes (General, Excluded Apps, Shortcuts, Cycles, Displays, Ring, Overlay, About), and every control can be reached with Tab. Settings → Overlay has a **Show on Screen** button that shows the real ring and preview for three seconds, so a theme can be judged without holding the trigger.

## Automation

Every surface below runs the same commands.

```bash
tessera apply --cols 2-4 --band top     # columns 2–4, top half
tessera action leftHalf
tessera cycle left
tessera columns --set 6 --display 2
tessera move next
tessera displays --json
tessera settings export ~/tessera.json
```

**Install the CLI.** In Settings → General, choose **Install Command-Line Tool**. It links the tool into `~/.local/bin/tessera`.

**URL scheme.** For example, `open "tessera://apply?cols=2-4&band=top"`. URLs cannot read or write files.

**AppleScript.** For example: `tell application "Tessera" to apply columns "2-4" band top`.

**Shortcuts and Spotlight.** Search for "Tessera" in the Shortcuts app.

## Status

| # | Milestone | Status |
|---|---|---|
| 1 | Engine, radial ring, display profiles, rich preview | built, awaiting hands-on test |
| 2 | Full keyboard control and automation (hotkeys, cycles, CLI, URL, AppleScript, Shortcuts) | built, awaiting hands-on test |
| 3 | Drag-to-snap | planned |
| 4 | Saved layouts with auto-restore on dock | planned |
| 5 | Multi-display throw and Spaces | planned |

Design documents:
- [Milestone 1](docs/superpowers/specs/2026-10-03-tessera-milestone1-design.md)
- [Milestone 2](docs/superpowers/specs/2026-10-03-tessera-milestone2-keyboard-automation-design.md)

## Requirements

- macOS 15 Sequoia or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```bash
swift test --package-path Packages/TesseraCore --scratch-path ~/Library/Caches/tessera-build/core-main
scripts/build-app.sh
```

The script prints the path to `Tessera.app`. Build output goes to `~/Library/Caches/tessera-build/`, because codesign fails inside iCloud-synced folders.

## Permissions

- **Accessibility (required):** used to move and resize other apps' windows. Builds are ad-hoc signed, so macOS asks for this again after each rebuild.
- **Screen Recording (optional):** only used for the live window thumbnail in the preview. Without it, Tessera shows a plain rectangle.

## Default trigger

Hold **Left Control + Left Option + Left Command**. You can change it in Settings → General.

## Layout

- `Packages/TesseraCore`: pure Swift logic, with no AppKit, and fully unit-tested:
  - the sizing rule and grid geometry
  - the selection engine
  - the trigger state machine
  - the preview model
  - the settings store
- `Tessera/`: the macOS app:
  - `Services/`: event tap, displays, Accessibility, thumbnails
  - `Overlay/`: ring, grid and preview panels
  - `UI/`: settings and onboarding

## Credits

Tessera is inspired by [Loop](https://github.com/MrKai77/Loop) by MrKai77. It is an independent implementation: no Loop source code is used.
