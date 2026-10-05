# Learned splits — design

Date: 5 October 2026
Status: decisions settled in design review (grilling); awaiting written-spec review
Scope: piece 1 of 3 (1 learned splits → 2 named layouts → 3 app memory with the Ring slot), delivered as two PRs: **1a engine**, **1b Splits pane**.

## Goal

Tile gives every visible window on a display an equal share. People rarely want equal: two Chrome windows at 30 / 70, an editor at half width beside two references, a strip of desktop left free on the right. Tessera should learn the arrangement a person sets by hand and reuse it the next time the same group of windows is tiled.

Success: tile, adjust the windows by hand once, and every later Tile of that group on that display reproduces it, including after Tessera relaunches.

## Principles from review

- Every behaviour with more than one reasonable answer is a **setting**, and each setting shows a **live preview** of what its options do (1b). Defaults are listed below.
- Learning is automatic but never silent: a short message says what was learned.
- Tessera still never moves a window unless the person triggers a command.

## Behaviour

### Groups

A group is **every visible window on one display**, using Tile's existing rules (excluded apps, minimised, hidden and tiny windows are left out). Its key is the display's stable storage key plus the multiset of bundle IDs, e.g. `C49 · Chrome ×2, Slack, Mail`. App order does not matter. The same apps with a different count, or on a different display, form a different group.

### What is learned

Each window's full rectangle, relative to the display's usable frame: position, width and height. Empty space is anything not covered, so strips at the edges and gaps between windows are learned too. Gaps no larger than the display's own gap setting (plus 8 pt) count as no gap.

Any **non-overlapping** arrangement is learned: rows, stacks, grids, uneven mixes. Windows overlapping by more than 24 pt are a messy desk, not a split, so nothing is learned and Remember explains why ("Windows overlap").

Rectangles are stored exactly (no snapping); the pane rounds for display.

### When it learns

- **After a Tile, and after Remember**, Tessera watches that group's windows. About one second after each hand adjustment ends, it re-reads the group and saves the arrangement.
- Watching continues until the group changes: a watched window closes, leaves the display, or a window joins; another Tile or Remember starts; learning is switched off; or Tessera quits.
- **Remember this split** saves the current arrangement of the display on demand, even if Tessera never tiled it, then watches as above. Surfaces: menu bar item, bindable command, CLI `tessera remember [--display D]`, AppleScript `remember split`.
- Each save shows a short message, "Learned split · Chrome ×2 · C49", through the existing message system (Show messages, position and duration apply).

### When it applies

Tile looks up the group's key.

- **Nothing learned:** equal shares, exactly as today.
- **Learned:** each window takes **its app's learned size**. Several windows of the same app pair with that app's learned rectangles: along the row (or column) when packing in current order, in reading order when restoring exact rectangles. Tile's message adds "· your split".

Where windows go depends on the **Restore last order** setting (default **off**):

- **Off:** windows keep their **current** order. In a single row (or a single column on a portrait display), windows are packed in current order, each at its app's learned width and height and vertical offset, with empty space placed by the **Empty space** setting:
  - **Stays in place** (default): each strip keeps its slot in the sequence (far right stays far right; a gap between positions 1 and 2 stays between positions 1 and 2) and its size.
  - **Follows its neighbour:** each strip stays attached to the window it sat beside (its right side; a leading strip to the first window's left).
  Both always fit, because the group's widths and gaps add up to the same extent.
- **On:** every window returns to its learned rectangle, so order and empty space are restored exactly.

**Grids and stacks** (more than one row or column) always restore learned rectangles, whatever Restore last order says: different-sized cells can't be repacked in a new order without overlap. The setting's preview shows this.

### Settings (all persisted in the settings file)

| Setting | Options | Default |
|---|---|---|
| Learn from my adjustments | on / off | on |
| Restore last order | on / off | off |
| Empty space when order changes | stays in place / follows its neighbour | stays in place |
| Empty space when a window grows (pane editing) | stays fixed / shrinks like a window | stays fixed |

Turning learning off stops all watching; Remember still works (explicit), and Tile still uses existing splits.

### Splits pane

A new Settings pane after Cycles. ⌘1–9 number the first nine panes; About moves to ⌘0.

- **1a:** list of learned splits grouped by display ("Chrome ×2 · C49"), Forget per split, Forget All, and the four settings as plain controls.
- **1b:**
  - Each split drawn as a miniature of its display: every window with its app icon and name, placed exactly as Tile will place it.
  - Drag a window's edge in the miniature to resize it; other windows give way proportionally, and empty space follows the "when a window grows" setting.
  - A **Show percentages** toggle (off by default) reveals each window's width, height and position as editable percentages for power users.
  - Each setting gets a live preview: a small animated miniature showing what each option does.

## Approach

Accessibility notifications, chosen over polling (wasteful, misses later adjustments) and over learning lazily at the next Tile (can learn a half-messed desk). After Tile or Remember, Tessera subscribes to move, resize and destroy notifications for exactly the group's windows, debounces, and learns once the person stops adjusting.

## Components

### Core (`Packages/TesseraCore`, pure Swift, unit-tested)

| Unit | Responsibility |
|---|---|
| `SplitKey` | Display storage key + sorted bundle-ID multiset. Stable string form for storage and display. |
| `LearnedSplit` | `key`, `slots: [Slot]` in reading order, `updated: Date`. `Slot` = bundle ID + unit rectangle (x, y, width, height in 0…1 of the usable frame). |
| `SplitLearner` | Frames in, `Result<[Slot], SplitRejection>` out. Rejects overlap beyond 24 pt; normalises to the usable frame; treats gaps up to the display gap + 8 pt as none. |
| `SplitApplier` | Learned split + current windows (bundle ID, frame) + settings in, target frame per window out. Implements app matching, the off / on order modes, both empty-space rules, the grid fallback, and the usable-frame scaling. |
| `SplitMemory` | Lookup by key, upsert (moves to newest), forget, forget all, cap at 50 (oldest dropped). |
| `SplitEditor` (1b) | Pure resize of one slot inside a split, applying the "when a window grows" rule; keeps every slot inside the frame and non-overlapping. |
| Settings | `learnSplits`, `splitRestoresOrder`, `splitGapPlacement`, `splitGapWhenGrowing`, `learnedSplits`. Missing keys are filled by `SettingsMigration`; no schema bump. Validation rejects non-finite or out-of-range rectangles and more than 50 splits; mismatched or overlapping slots are tolerated (the applier falls back to equal shares on a mismatch) so a stale split can never quarantine the whole settings file. |
| Command | `.rememberSplit(display: DisplaySelector)`; `CommandParser` grammar `remember [--display D]`; Shortcuts-pane summary. |

### App (`Tessera/`)

| Unit | Responsibility |
|---|---|
| `SplitWatcher` (new file) | `@MainActor`. One `AXObserver` per app for move, resize and destroy. Ignores events until Tessera's own moves (and glide) finish. Debounces 1 s, re-reads the group via `WindowService`, runs `SplitLearner`, upserts, posts the message. Stops on the group-change conditions above. |
| `CommandExecutor+Splits.swift` (new) | Builds the key, applies `SplitApplier` inside Tile, implements Remember, starts the watcher. Keeps `CommandExecutor.swift` under 300 lines. |
| `SplitsPane` (new file) | 1a list and controls; 1b miniature editor, percentages, previews (split into sub-views to stay under 300 lines each). |
| `SettingsPane` | New `splits` case after `cycles`; About on ⌘0. |
| Menu bar / AppleScript | "Remember Split" item; `remember split` script command. |

## Data flow

```
Tile ─► visibleWindows ─► SplitKey ─► SplitMemory.lookup ─┬─ none ─► GridGeometry.tiles (equal)
                                                          └─ found ─► SplitApplier ─► frames
                                                                         │
                                     place ×N (one undo step) ─► SplitWatcher.watch(after: moves end)
                                                                         │
person adjusts ─► AX notifications ─► debounce 1 s ─► read frames ─► SplitLearner ─► SplitMemory.upsert
                                                                         │
                                                         settings save + "Learned split" message
```

## Edge cases

- **Window can't reach its size** (minimum width): existing re-anchoring keeps it on its edge; learning reads actual frames, so an impossible size is never stored.
- **Group changes mid-watch:** watching stops; nothing is learned from a partial group.
- **Display unplugged:** its splits stay stored and apply when it returns.
- **Display resolution or Dock change:** rectangles are relative to the usable frame, so they scale.
- **Accessibility revoked mid-watch:** callbacks stop; watching ends quietly.
- **Undo:** a Tile with a learned split is still one ⌃⌥Z step. Undoing doesn't teach Tessera anything, because watching ignores Tessera's own moves.

## Testing

Core (Swift Testing):
- `SplitLearner`:
  - rows, stacks and grids accepted
  - overlap beyond tolerance rejected
  - small gaps treated as none, large gaps kept
  - normalisation to the usable frame; portrait
- `SplitApplier`:
  - app matching, including duplicates (along the axis when packing, reading order when restoring)
  - order off: stays-in-place and follows-neighbour gap rules on rows
  - order on: exact restore
  - grid fallback
  - scaling to a different usable frame
  - equal fallback when nothing is learned
- `SplitMemory`: lookup, upsert-to-newest, forget, forget all, cap at 50.
- `SplitKey`: app-order independence; count and display sensitivity.
- `SplitEditor` (1b): proportional shrink, both gap rules, bounds and non-overlap.
- Settings: old file decodes with defaults; validation rejects bad slots.
- `CommandParser`: `remember`, `remember --display 2`.

Manual (signed build):
1. Tile two Chrome windows, drag to about 30 / 70 and confirm the message; Tile again and confirm 30 / 70.
2. Relaunch Tessera and confirm the split again.
3. Leave a strip on the right and confirm it returns.
4. Swap two apps and check both empty-space settings.
5. Build a 2×2 grid and Remember it.
6. Forget, and confirm Tile is equal again.

## Out of scope

- Named layouts (piece 2).
- App memory (piece 3): close-size memory, optional position, Ring-only restore, and the "tiled apps only / every app" setting.
- Moving windows automatically on app launch.
