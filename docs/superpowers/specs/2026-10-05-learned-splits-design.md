# Learned splits — design

Date: 5 October 2026
Status: approved in conversation; awaiting written-spec review
Scope: piece 1 of 3 (1 learned splits → 2 named layouts → 3 remembered slot in the Ring)

## Goal

Tile currently gives every visible window on a display an equal share. People rarely want equal: two Chrome windows at 30 / 70, or editor + two references at 50 / 25 / 25. Tessera should learn the proportions a person sets by hand and reuse them the next time the same group of windows is tiled.

Success: tile, drag to the split you want once, and every later Tile of that same group on that display reproduces it, including after Tessera relaunches.

## Behaviour

1. **Tile looks up a learned split.** The group key is the display plus the apps and how many windows each has (for example `C49 · Chrome ×2`). App order does not matter.
   - No learned split: equal shares, exactly as today.
   - Learned split: its shares, for example 30 / 70.
   - Windows keep today's ordering rule (left to right; top to bottom on a portrait display) to decide which window takes which share.
2. **Automatic learning after Tile.** Hand adjustments to the tiled windows update that group's shares about one second after the last drag.
3. **Remember this split.** A new command saves the shares of whatever sits side by side on a display now, even if Tessera never tiled it. Available from the menu bar, a bindable hotkey, the CLI (`tessera remember [--display D]`) and AppleScript (`remember split`).
4. **Only clean rows are learned.** Windows must sit side by side along the tiling axis (columns; rows on a portrait display) and span the usable area. A 2×2 grid or overlapping windows is not a split: nothing is saved, and Remember says why ("Windows aren't side by side").
5. **Settings → Splits pane.** Lists every learned split ("Chrome ×2 · C49 · 30 / 70") with a Forget button per row and Forget All, plus a "Learn from my adjustments" switch (on by default). The pane will also host named layouts in piece 2.
6. **Persistence.** Learned splits live in the settings file, so they survive restarts. Undo (⌃⌥Z) still reverts a whole Tile in one step.

## Approach

Resize notifications (chosen over polling, which wastes CPU and misses later adjustments, and over learning lazily at the next Tile, which can learn a half-messed desk).

After a Tile, Tessera subscribes to Accessibility move/resize/destroy notifications for exactly the tiled windows, debounces them, and learns when the person stops dragging.

## Components

### Core (`Packages/TesseraCore`, pure Swift, unit-tested)

| Unit | Responsibility |
|---|---|
| `SplitKey` | Value type: display storage key + sorted multiset of bundle IDs + axis. Stable string form for storage and display. |
| `LearnedSplit` | `key`, `shares: [Double]` (each > 0, sum 1, count = window count), `updated: Date`. |
| `SplitLearner` | `shares(frames: [CGRect], in usable: CGRect, axis: Axis) -> Result<[Double], NotARow>`. Orders frames along the axis, accepts gaps and overlaps up to a tolerance (default 24 pt or the display's gap, whichever is larger), requires the row to cover at least 90 % of the usable extent, and normalises out gaps and padding. |
| `GridGeometry.tiles(_:display:shares:)` | Weighted version of today's `tiles`. `shares == nil` or a count mismatch falls back to equal shares. Gap and padding behave as today. |
| `SplitMemory` | Pure operations on `[LearnedSplit]`: lookup by key, upsert (moves the entry to newest), forget one, forget all, cap at 50 entries (oldest dropped). |
| Settings | `learnedSplits: [LearnedSplit] = []`, `learnSplits: Bool = true`. Missing keys are filled by `SettingsMigration`; no schema bump. Validation rejects shares that are non-finite, ≤ 0, or don't sum to 1 ± 0.001. |
| Command | `.rememberSplit(display: DisplaySelector)`, with CLI grammar `remember [--display D]` in `CommandParser` and a summary for the Shortcuts pane. |

### App (`Tessera/`)

| Unit | Responsibility |
|---|---|
| `SplitWatcher` (new file) | `@MainActor`. `watch(_ windows: [WindowRef], key: SplitKey, display: DisplayContext, after: Date)`. One `AXObserver` per app; observes `kAXMovedNotification`, `kAXResizedNotification`, `kAXUIElementDestroyedNotification`. Ignores events before `after` (the end of Tessera's own glide). Debounces 1 s, reads the frames through `WindowService`, asks `SplitLearner`, and on success upserts into settings. Stops when a watched window is destroyed, leaves the display, a new `watch` starts, or learning is switched off. |
| `CommandExecutor.tile` | Builds the `SplitKey`, looks up shares, calls the weighted `tiles`, and after the moves hands the windows to `SplitWatcher`. File stays under 300 lines; any extra logic goes in a sibling `CommandExecutor+Splits.swift`. |
| `CommandExecutor.rememberSplit` | Reads visible windows on the resolved display, asks `SplitLearner`, saves or reports why not. |
| `SplitsPane` (new file) | List of learned splits grouped by display, Forget / Forget All, the learning switch. |
| `SettingsPane` | New case `splits`, placed after `cycles`. ⌘1–9 keep numbering the first nine panes; About moves to ⌘0. |
| Menu bar | "Remember Split" item next to Tile. |

## Data flow

```
Tile ─► visibleWindows ─► SplitKey ─► SplitMemory.lookup ─► GridGeometry.tiles(shares:) ─► place ×N
                                                                                   │
                                                              SplitWatcher.watch(after: glide end)
                                                                                   │
     person drags an edge ─► AX notifications ─► debounce 1 s ─► read frames ─► SplitLearner
                                                                                   │
                                                              SplitMemory.upsert ─► settings save
```

## Edge cases

- **A window can't shrink far enough.** The share is a target; the existing re-anchoring keeps the constrained window on its edge. Learning reads actual frames, so it never stores an impossible share.
- **Group changes mid-watch** (a window closes, moves display, or a new window joins). The watch stops; nothing is learned from a partial group.
- **Unplugged display.** Its splits stay stored and apply again when it returns (the key uses the display's stable storage key).
- **Same apps, different count** (Chrome ×2 vs Chrome ×3). Different keys; each learns separately and starts equal.
- **Excluded apps and tiny windows.** Same exclusions as Tile today, applied before the key is built, so they never affect a group.
- **Learning switched off.** No watcher starts; Remember still works (it's explicit). Existing splits are still used by Tile.
- **Accessibility revoked mid-watch.** Observer callbacks stop; the watch ends silently.

## Testing

Core (Swift Testing, about 15 new tests):
- `SplitLearner`: clean two- and three-window rows; gaps and padding normalised out; overlap within tolerance accepted; 2×2 grid, overlapping and partial-coverage rows rejected; portrait axis.
- `GridGeometry.tiles(shares:)`: weighted widths sum to the usable extent minus gaps; `nil` and count mismatch fall back to equal; portrait.
- `SplitMemory`: lookup, upsert-moves-to-newest, forget, forget all, cap at 50.
- `SplitKey`: app order independence; different counts differ; different displays differ.
- Settings: old file without the new keys decodes with defaults; validation rejects bad shares.
- `CommandParser`: `remember`, `remember --display 2`.

Manual (signed build): tile two Chrome windows, drag to roughly 30 / 70, wait a second, Tile again and confirm 30 / 70; relaunch Tessera and confirm again; use Remember on a hand-made arrangement; Forget in the Splits pane and confirm Tile returns to equal.

## Out of scope

Named layouts (piece 2), the remembered slot in the Ring (piece 3), and two-dimensional splits (grids).
