# Tessera

A macOS window manager that fits its grid to each display's size.

Hold the trigger chord, then **flick** or **point** to snap the frontmost window:

- **Flick:** a short flick picks a wedge from the ring (halves, quarters, maximise, centre).
- **Point:** move further and point at a column. Each display gets its own grid, sized from its usable resolution. A 14" MacBook gets halves and quarters. A 49" 32:9 ultrawide gets 5 columns by default.
  - **Scroll** while holding to change the column count. Tessera remembers it per monitor.
  - **Click** while holding to span a window across several columns.

The preview shows:
- a live thumbnail of the window in its new spot
- the exact size and slot
- dimming on the windows it will cover
- an outline of where the window was

Tile All Windows and Tile Evenly arrange every window on a display at once, and Tessera learns the splits you adjust by hand. ⌃⌥Z undoes any move, and **What Just Happened?** in the menu bar explains the last one.

You can change the trigger, hotkeys, cycles, column counts, theme and motion. Settings export and import as one JSON file.

**New to Tessera?** Read the [User Guide](docs/USER-GUIDE.md). It covers the features and settings with examples.

## Install

Tessera is free and in public beta.

1. Download the latest `Tessera-….zip` from [Releases](https://github.com/prabeshbhetwal/tessera/releases) and move `Tessera.app` to Applications.
2. The beta is not yet notarised by Apple, so macOS blocks the first launch. Open it once, then go to System Settings › Privacy & Security and choose **Open Anyway**.
3. Grant Accessibility when asked. Updates install from the menu bar after that.

## Privacy

Tessera has no analytics, no accounts and no telemetry. Settings stay on your Mac.

- **Update checks:** Tessera fetches its update feed from GitHub (`raw.githubusercontent.com`). GitHub sees your IP address and Tessera's version, as with any download.
- **Screen Recording:** window thumbnails are drawn on this Mac for the preview and discarded. They are never saved or sent.
- **Accessibility:** used only to read and move windows.

## Licence

Tessera is free software under the [GNU General Public License v3.0](LICENSE). It comes with no warranty. Bundled components are listed in [Third-party notices](THIRD-PARTY-NOTICES.md).

To report a security issue, see [SECURITY.md](SECURITY.md).

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

**Hotkeys.** These work without the ring, and you can rebind all of them in Settings › Shortcuts:

| Key | Action |
|---|---|
| ⌃⌥← / ⌃⌥→ | Cycle: half, edge column, two columns |
| ⌃⌥↑ | Maximise |
| ⌃⌥↓ | Centre |
| ⌃⌥1–9 | Column N |
| ⌃⌥= / ⌃⌥− | Columns ±1 |
| ⌃⌥N / ⌃⌥P | Next / previous display |
| ⌃⌥Z | Undo |
| ⌃⌥⌘, | Settings |

**Settings window.** ⌘1–9 switches panes (General, Excluded Apps, Shortcuts, Cycles, Splits, Displays, Ring, Overlay, Motion) and ⌘0 opens About, and every control can be reached with Tab. Settings › Overlay has a **Show on Screen** button that shows the real ring and preview for three seconds, so you can judge a theme without holding the trigger.

## Automation

Each surface below runs its supported commands through the same executor.

```bash
tessera apply --cols 2-4 --band top     # columns 2–4, top half
tessera action leftHalf
tessera cycle left
tessera columns --set 6 --display 2
tessera move next
tessera remember                        # save how the windows are arranged now; Tile reuses it
tessera displays --json
tessera settings export ~/tessera.json
```

**Install the CLI.** In Settings › General, choose **Install Command-Line Tool**. It links the tool into `~/.local/bin/tessera`.

**URL scheme.** For example, `open "tessera://apply?cols=2-4&band=top"`. URLs cannot read or write files.

**AppleScript.** For example: `tell application "Tessera" to apply columns "2-4" band top`.

**Shortcuts and Spotlight.** Search for "Tessera" in the Shortcuts app.

## Status

| # | Milestone | Status |
|---|---|---|
| 1 | Engine, radial ring, display profiles, rich preview | in public beta (0.2.0) |
| 2 | Full keyboard control and automation (hotkeys, cycles, CLI, URL, AppleScript, Shortcuts) | in public beta (0.2.0) |
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

**Run.** Open the app path printed by the build script:

```bash
app="$(scripts/build-app.sh)"
open "$app"
```

Complete Accessibility setup, focus a window in another app, then hold the default trigger and flick towards a wedge icon. Choose **Quit Tessera** in its menu bar menu to stop the event tap and CLI socket.

**Checks without moving desktop windows:**

```bash
bash scripts/verify-automation.sh
bash scripts/verify-ring-rendering.sh /tmp/tessera-ring-preview-new.png
bash scripts/verify-app-packaging.sh "$app"
```

Choose a fresh Ring output filename. The automation check uses a temporary owner-only socket and a test executor; it does not load personal settings or run window commands.
The packaging check verifies bundle resources, signature and embedded CLI help/usage without launching Tessera. CI also runs the production Ring checks and retains their synthetic preview for seven days.
CI's native automation smoke refuses existing app data and verifies real CLI/settings and read-only window-query contracts against the runner's measured Accessibility capability. It never grants permissions or performs window actions.

## Permissions

- **Accessibility (required):** used to move and resize other apps' windows. The build script uses **Tessera Local Signing** when that identity is available, preserving the grant across rebuilds. Other machines fall back to ad-hoc signing and may need a fresh grant after rebuilding. This local signature does not establish Developer ID signing or notarisation.
- **Screen Recording (optional):** only used for the live window thumbnail in the preview. Without it, Tessera shows a plain rectangle.

## Default trigger

Hold **Left Control + Left Option + Left Command**. You can change it in Settings › General.

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
