# Tessera: Milestone 2 design spec, keyboard + automation

- **Date:** 2026-10-03
- **Status:** approved in chat on 2026-10-03
- **Builds on:** `2026-10-03-tessera-milestone1-design.md`. Every M1 constraint still applies.
- **Replaces:** the old M2 ("keyboard shortcuts + cycles"). This spec covers that scope and adds automation.

## 1. Purpose
Everything Tessera can do must be possible from the keyboard alone, and from automation. Keyboard-first users never need the mouse. Scripts and other apps can drive every action.

**Success criteria:**
1. With only the keyboard, a user can hold the chord, pick any column, span, band or display with nav keys, and apply.
2. Every command is reachable from:
   - a rebindable global hotkey
   - a `tessera://` URL
   - the `tessera` CLI
   - AppleScript
   - the Shortcuts app and Spotlight (App Intents)
3. Hotkey cycles advance on repeated presses and skip steps that would not change the window.
4. Settings and onboarding work fully by keyboard: Tab order, ⌘1–8 to switch panes, and recorders that need no mouse.
5. A v1 `settings.json` migrates to v2 automatically. The user's data is never reset.

## 2. One command language
Every surface turns input into a `Command` (TesseraCore, Codable). One `CommandExecutor` in the app runs it and returns a `CommandResult`.

| Command | Meaning |
|---|---|
| `apply(Target, display:)` | Move or resize the frontmost window |
| `cycle(name:)` | Run the next step of a named cycle |
| `columns(ColumnChange, display:)` | `set(n)` or `delta(±n)`, clamped to the display's range and saved as an override |
| `moveToDisplay(DisplayStep)` | `next`, `previous` or `index(n)`. Keeps the window's relative column and band, scaled to the new grid. |
| `undo` | Undo the last move |
| `openSettings` | Open the Settings window |
| `listDisplays` | Returns `[DisplayInfo]` |
| `describeWindow` | Returns `WindowInfo` |
| `exportSettings(path:)` / `importSettings(path:)` | Settings as JSON |

### Target
- `.action(WindowAction)`, or
- `.span(columns: ClosedRange<Int>, band: Band)`
  - Columns are **1-based**.
  - **Negative numbers count from the right:** `-1` is the last column, so `-2...-1` means the last two.
  - The range is clamped to the display's current column count.

### DisplaySelector
| Selector | Meaning |
|---|---|
| `current` | The display containing the frontmost window's centre (default) |
| `cursor` | The display under the cursor |
| `index(n)` | Displays sorted by `frame.minX`, then `frame.minY`; 1-based |
| `id(storageKey)` | A specific display |

`DisplayStep` uses the same ordering and wraps around at the ends.

### Text syntax (URL and CLI)
- **Columns:** `2`, `2-4`, `2..4`, `-1`, `-2..-1`. Use `..` whenever a negative number is involved.
- **Band:** `full`, `top` or `bottom`.
- **Display:** `current`, `cursor`, `1`…`n`, or `id:<key>`.

**URL examples:**
- `tessera://apply?cols=2-4&band=top&display=cursor`
- `tessera://action/leftHalf`
- `tessera://cycle/left`
- `tessera://columns?set=6&display=2`
- `tessera://columns?delta=-1`
- `tessera://move?display=next`
- `tessera://undo`
- `tessera://settings/open`

**CLI:**
- `tessera apply --cols 2-4 --band top --display cursor`
- `tessera action leftHalf`
- `tessera cycle left`
- `tessera columns --set 6 --display 2`
- `tessera move next`
- `tessera undo`
- `tessera displays [--json]`
- `tessera window [--json]`
- `tessera settings export|import <path>`
- `tessera settings open`

Invalid input returns a clear error and never moves a window.

## 3. Ring keyboard navigation
While the chord is held and the ring is open:

| Key | Effect |
|---|---|
| ← / → | Move the selection one column; a span collapses to one column |
| ⇧← / ⇧→ | Extend the span left or right |
| ↑ / ↓ | Band: bottom → full → top, and back |
| 1–9 | Jump to that column, clamped |
| `=` / `-` | Column count +1 / −1 on the selected display |
| Tab / ⇧Tab | Next / previous display, keeping the column ratio |
| Return | Apply and close |
| Esc | Cancel |
| Any other key | If it matches a hotkey with the current modifiers: cancel the ring, run that hotkey, and swallow the key. Otherwise cancel and pass the key through (M1 behaviour). |

**How the selection behaves:**
- **Where it starts:** on the first nav key, at the frontmost window's display and the column under the window's centre, with band `full`.
- **Which input wins:** the most recent one. A mouse move of at least 10 pt after a nav key switches back to cursor selection.
- **Releasing the chord:** applies the current selection, as in M1.
- **VoiceOver:** when `announceSelection` is on (the default), the label text is posted as an accessibility announcement on every selection change.

## 4. Global hotkeys and cycles

### Matching
- A `Hotkey` is a keyCode plus **side-agnostic** `Modifiers` (control, option, command, shift, function), and must match **exactly**.
- Hotkeys work while the ring is closed, and also through the ring-open path in §3.
- A matched hotkey's key event is swallowed.

### Defaults
All defaults can be rebound.

| Hotkey | Command |
|---|---|
| ⌃⌥← | cycle `left`: left half → column 1 → columns 1–2 |
| ⌃⌥→ | cycle `right`: right half → column −1 → columns −2…−1 |
| ⌃⌥↑ | maximize |
| ⌃⌥↓ | center |
| ⌃⌥1 … ⌃⌥9 | `apply(.span(n...n, .full), display: .current)` |
| ⌃⌥= / ⌃⌥− | `columns(.delta(±1), display: .current)` |
| ⌃⌥N / ⌃⌥P | move to next / previous display |
| ⌃⌥Z | undo |
| ⌃⌥⌘, | open Settings |

### Cycles
- A repeat of the same cycle on the same window within **2 s** advances to the next step, wrapping at the end. Anything else restarts the cycle at step 0.
- A step whose resolved frame equals the window's current frame (within 1 pt) is skipped. At most one full pass is made.

### Conflicts
The Shortcuts pane flags:
- duplicate bindings
- bindings that match an enabled system shortcut (`CopySymbolicHotKeys`)
- bindings whose modifiers equal the trigger chord with no key

These are warnings, not blockers.

## 5. Automation surfaces
All surfaces call `CommandBridge.execute(_:)`, which forwards to the executor.

| Surface | Details |
|---|---|
| **URL scheme** | `tessera`. Fire-and-forget. Errors are logged and shown in a HUD. **Security:** any web page can open a `tessera://` link, so URLs reject file commands (`settings export`/`import`) and queries (`displays`, `window`). Use the CLI, AppleScript or Shortcuts for those. |
| **CLI** | A `tessera` executable built from the TesseraCore package (`TesseraCLI` target) and embedded at `Tessera.app/Contents/Helpers/tessera` (not `MacOS/`, which collides with the app binary `Tessera` on case-insensitive APFS). Talks to the running app over a Unix domain socket at `~/Library/Application Support/Tessera/tessera.sock`, mode 0600, created by the app. Protocol: one request line (Command JSON) and one response line (CommandResult JSON). Exit codes: 0 ok, 1 command error, 2 usage error, 3 app not running. Settings → General has an **Install CLI** button that symlinks it to `~/.local/bin/tessera` and shows a PATH hint. |
| **AppleScript** | `Tessera.sdef` with these commands: `apply columns "2-4" band top display "cursor"`, `perform action "leftHalf"`, `run cycle "left"`, `set columns 6 display "2"`, `change columns by -1`, `move to display "next"`, `undo move`, `list displays` (returns records), `describe window`, `open settings`. `NSAppleScriptEnabled` is on. |
| **App Intents** | Intents for each command: Apply Columns, Perform Action, Run Cycle, Set Columns, Change Columns, Move to Display, Undo, List Displays, Describe Window, Open Settings. `DisplayEntity` lets Shortcuts pick a display. An `AppShortcutsProvider` exposes Spotlight phrases such as "Tessera maximize". The intents run in-process; `openAppWhenRun` is false. |

## 6. Keyboard-usable UI
- **Settings:** ⌘1–8 switches panes. Every control is focusable in a logical Tab order.
- **Recorders:** the chord and hotkey recorders start with Space or Return and finish on key-up. Esc cancels recording, and Delete clears the binding.
- **New Shortcuts pane:**
  - a list of bindings, each with recorder, command picker, enabled toggle and conflict badge
  - add, remove and "restore defaults"
  - a **cycles editor**: an ordered list of targets, reordered with ⌘↑ / ⌘↓
- **Onboarding:** Return continues, Esc skips the optional step, and every button is reachable by keyboard.
- **Menu bar menu:** the native menu is already keyboard-navigable. Add a "Shortcuts…" item.

## 7. Settings schema v2
New fields:
- `hotkeys: [HotkeyBinding]`, default from §4
- `cycles: [Cycle]`, default `left` and `right`
- `ringKeyNavigation: Bool = true`
- `announceSelection: Bool = true`

**Migration:** `schemaVersion` becomes 2. A v1 file is migrated by adding the new keys with their defaults, then saved back as v2. The original v1 file is first copied to `settings.v1-backup.json`.

## 8. Testing
- **TesseraCore (Swift Testing):**
  - CommandParser: every URL and CLI form, plus the error cases
  - target and display resolution, including negative columns, clamping and wrap-around
  - KeyNavigator: every key, and the clamps
  - CycleTracker: timeout, advance and reset
  - HotkeyTable: exact modifier matching and conflict detection
  - the TriggerMachine nav and hotkey paths
  - v1 → v2 migration
- **App:** build-checked, plus a coordinator reviewer pass.
- **Manual:** a keyboard-only session on the MacBook and on the CHG90; `tessera displays --json`; one Shortcuts action; one AppleScript; one URL.
