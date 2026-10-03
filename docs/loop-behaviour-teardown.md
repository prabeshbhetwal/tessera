# Loop behaviour teardown

Date: 2026-10-03

This document describes how Loop behaves, so we can build our own app from scratch. It is written in our own words and contains no Loop source code. Loop is GPL-3.0, so we reuse ideas, never code. The path prefix for every reference is `loop/Loop/`.

---

## 1. Features

### Trigger and radial menu
Files: `Core/LoopManager.swift`, `Core/Observers/KeybindTrigger.swift`

- **Default trigger:** Fn/Globe. Hold it to open the menu, release it to apply the selection.
- **Globe tap still works:** if you tap Globe without moving the mouse, the tap passes through to macOS for the emoji picker.
- **Trigger delay:** 0–1 s, in 0.1 s steps. Default 0.
- **Double-tap:** the gap must be at most 0.4 s, or the system double-click time if that is shorter.
- **Middle-click:** hold the middle button and drag.
- **Left and right modifiers** count as different keys by default.
- **Esc** cancels. A system shortcut (for example a screenshot) force-closes the menu.

### Keybinds
File: `Window Management/Window Action/WindowAction+Defaults.swift`

- A keybind is the trigger plus a key.

| Key | Action |
|---|---|
| Space | Maximize |
| Return | Center |
| Arrow | Cycle that edge: half → third → two-thirds |
| Two arrows together | Quarter |

- Holding grow, shrink, move or focus keybinds auto-repeats them.
- "Unlink Trigger Key" (right-click a keybind) turns it into a standalone global hotkey.

### Cycles
Files: `CycleActionCoordinator.swift`, `CycleProgressStore.swift`

- A cycle is a named list of actions.
- To advance: press the same keybind again, left-click while the menu is open, or continue a gesture.
- Shift steps backward.
- Progress is kept per window. A setting can make every cycle restart from the first item.

### Drag-to-snap
Files: `Core/WindowDragManager.swift`, `WindowDirection+Snapping.swift`

Off by default.

**Edge bands**
- Side edges: 2 pt wide.
- Top edge: max(half the menu bar height, 2 pt).

**Top edge**

| Position along the edge | Result |
|---|---|
| Within 1% of either end | Corner quarter |
| 1–20% or 80–99% | Top half |
| 20–80% | Maximize |

**Long-axis edges**

| Position along the edge | Result |
|---|---|
| Within 1% of an end | Corner quarter |
| 1–6.3% from an end | That end's half |
| 6.3–33% from an end | That end's third |
| Middle | Half |

From an outer zone, moving back to the middle gives the centre third. Moving more than 5% past the midpoint gives two-thirds.

**Short-axis edges:** corner quarter, otherwise half.

**Other behaviour**
- Shows a warning if macOS's own edge tiling is on, but only after you turn snapping on.
- Suppresses Mission Control by nudging the cursor 1 px down.

### Stash
File: `Stashing/StashManager.swift`

- Stashing slides a window off the left, right or bottom edge. A strip stays visible: 20 px by default (range 1–100), capped at 20% of the window.
- Hovering the strip reveals the window. Only one window is revealed at a time.
- Windows stack on an edge if each keeps at least 100 pt visible.
- Focus moves to another window when one is stashed. Everything is restored when the app quits.
- Mouse input is debounced at 50 ms. Reveal and hide are throttled to once per 100 ms.

### Trackpad gestures
Files: `Core/Multitouch/*`, `GestureBinding.swift`

Off by default.

- **Default gesture:** a 2-finger swipe or magnify on a titlebar opens the radial menu.
  - Swipe direction picks a wedge.
  - Pinch or spread picks the centre action.
  - Keep going to step through a cycle: every 0.15 of travel for swipes, every 0.2 for magnify.
- **Where gestures work:** 1–2 finger gestures only on the titlebar (a 50 pt band). Gestures with 3+ fingers can work anywhere.

### Focus navigation
Focus up, down, left or right picks the nearest aligned window in that direction. "Next in stack" is also available. Focus changes immediately, not on release.

### Multi-display
- **Actions:** next, previous, left, right, top and bottom screen.
- **Placement:** the window keeps its proportional frame, or the last action is re-applied on the new screen.
- **Target screen:** by default, the screen under the cursor.

### Spaces (prerelease)
Move a window to the next or previous Space, or to Space 1–16.

### URL scheme
File: `Core/URLCommandHandler.swift`

`loop://` supports `direction`, `screen`, `action`, `keybind` and `list`.

### Theming
- **Accent colour:** System, Wallpaper or Custom, with an optional gradient.
- **App icons:** 13 icons unlock as usage grows, from 25 to 5000 "loops".

### Updater
- First check 5 s after launch, then every 6 h.
- Auto-update and the dev channel are both off by default.

### Other
- Excluded apps.
- Ignore fullscreen windows.
- iCloud settings sync (hidden setting, on by default).
- Haptic feedback when the selection changes.

---

## 2. Window actions and geometry
Files: `WindowDirection.swift`, `WindowFrameResolver.swift`, `PaddingConfiguration.swift`

### Bounds
1. Start from the screen's visible frame (no menu bar, no Dock).
2. If Stage Manager is respected and its strip is visible, subtract the strip width: 150 by default, range 50–250.
3. Inset by screen padding: top, bottom, left, right, plus "external bar" for third-party menu bars.

### Fractions of the bounds
- **Maximize** (fullscreen uses the same frame).
- **Almost maximize:** 90%, centred.
- **Halves:** top, bottom, left, right, horizontal centre (x from 25% to 75%), vertical centre.
- **Quarters:** the four corners.
- **Thirds:** left, centre and right thirds, plus left and right two-thirds. The same set exists vertically.
- **Fourths:** first to fourth, plus left and right three-fourths.

### Gaps
- Each window edge that does not touch the bounds is inset by half a gap. Neighbouring windows therefore end up exactly one gap apart.
- Center actions never get gaps.
- A non-resizable window is centred inside its target rectangle, then clamped to the bounds.
- **Padding range:** 0–100 px. "Simple" mode uses one value everywhere; "Custom" sets each side.

### Other actions

| Action | What it does |
|---|---|
| Center | Keeps the current size and centres the window. |
| macOS Center | Centres slightly high, like the system does. |
| Maximize height / width | Fills one axis and keeps the other. |
| Fill available space | Largest rectangle that overlaps no other window. |
| Larger / smaller | Moves every edge that is not touching the bounds by the size increment (default 20 px, range 5–50). |
| Scale up / down | Proportional, around the window's centre. |
| Grow / shrink | One edge or one axis. |
| Move | Shifts the window by the size increment. |
| Undo | Returns to the previous recorded frame. |
| Initial frame | Restores the frame from before Loop first touched the window. |
| Hide, minimize, minimize others | Standard window commands. |

- **Minimum window size:** preview padding + 100 px.
- **Custom action:** sizes in px or %. Size can be custom, preserved or the initial size. Position is an anchor (8 edges and corners, center, macOS center) or x/y coordinates.

---

## 3. Radial menu interaction
Files: `Core/Observers/MouseInteractionObserver.swift`, `Window Action Indicators/Radial Menu/*`

### Size and placement
- Opens centred on the cursor. A hidden setting locks it to the screen centre.
- Visual size is 100 pt, inside a 180 pt panel.
- **Corner radius:** 50 (range 30–50). At 48 or more the menu is drawn as a circle; below that, as a rounded square.
- **Thickness:** 22 (range 10–35).

### Hit zones (distance from where the menu opened)

| Distance | Result |
|---|---|
| Less than 10 pt | No selection |
| 10 pt to (50 − thickness) | Centre action (10–28 pt at default thickness) |
| Beyond that | Directional wedge |

### Wedges
- The circle is split into 360° ÷ (number of actions − 1) wedges. The first wedge is centred straight up; the rest go clockwise.
- **Defaults** (8 wedges of 45°):
  - Top, right, bottom and left: edge cycles.
  - The four diagonals: quarters.
  - Centre: a cycle of maximize → macOS center.

### Edge handling
If the menu opens within 50 pt of a screen edge, cursor travel is tracked virtually up to 50 pt past the edge.

### Applying a selection
- Preview on: the frame is applied when you release the trigger.
- Preview off: each selection is applied live as you move.
- No selection on release does nothing.

### Feedback
- A "fill" action (maximize or center) fills the ring and shrinks it to 0.85 scale.
- A warning glyph shows when there is no target window.

### Animation presets

| Preset | Preview duration |
|---|---|
| Fluid | 0.325 s |
| Relaxed | 0.30 s |
| Snappy (default) | 0.25 s |
| Brisk | 0.15 s |
| Instant | None |

- Selector rotation: 0.2 s.
- The menu appears in 0.1 s and closes in 0.15 s.
- Window movement is not animated by default, and never in Low Power Mode.

### Preview overlay
- A full-screen overlay drawn just under the menu.
- **Padding:** 10 (range 0–20).
- **Border:** 4 (range 0–10).
- **Corner radius:** 10 (range 0–25), or the window's own radius.
- Blur on, with a 10% accent tint.

---

## 4. Settings surface

Ten panes. Defaults are in brackets.

### Theming
- **Icon:** picker; show in Dock [off]; notify on unlock [on].
- **Accent:** mode [System]; gradient [off].
- **Radial Menu:** on [on], radius [50], thickness [22]. The action list only appears when Advanced customization is turned on.
- **Preview:** on [on], padding [10], border [4], use window radius [on], radius [10], blur [on], opacity [10%].

### Behaviour
- **General:** launch at login [off], start hidden [off], hide menu bar icon [off], animation [Snappy].
- **Window:** move to cursor's screen [on], restore frame on drag [off], padding [off].
- **Cursor:** move cursor with window [off], resize window under cursor [off], focus on resize [on].
- **Snapping:** snapping [off], suppress Mission Control [on].
- **Stage Manager:** respect strip [on], strip size [150].
- **Stash:** animate [on], peek size [20], shift focus [on].

### Keybinds
- Trigger [Fn]; left and right sides differ [on]; delay [0].
- Hide menu when nothing is selected [off]; double-click [off]; middle-click [off].
- Restart cycles [off]; Shift goes backward [on].
- The keybind list.

### Gestures
On [off], plus the list of gestures.

### Advanced
- Use the macOS window manager [off]; animate resize [off]; disable cursor interaction [off].
- Ignore fullscreen windows [off]; haptics [on]; size increment [20].
- Allow radial customization [off].
- Keybinds import / export / reset; Accessibility request button.

### Excluded Apps and About
About covers version, dev builds [off], auto-update [off] and links.

### Hidden (Terminal only)
- Lock the menu to the screen centre.
- Minimum screen size for padding; ignore the notch.
- Snap threshold [2].
- Ignore Low Power Mode.
- Preview start position.
- Trigger timeout.
- Gesture titlebar height [50].
- iCloud sync [on].

---

## 5. Onboarding and permissions
Files: `App/AppDelegate.swift`, `Utilities/AccessibilityManager.swift`

There is no wizard. On launch, Loop:
1. Opens Settings, unless it was launched at login or "start hidden" is on.
2. Asks for notification permission right away. Notifications are only used for icon unlocks.
3. Tells older running copies to quit, and waits up to 3 s.
4. Silently resets its Accessibility and Input Monitoring permission entries.
5. Shows a modal alert, then the system Accessibility prompt.

Permission changes are watched, and input monitoring starts or stops to match. If permission is revoked, the trigger stops without telling the user.

---

## 6. UX weak points (our opportunities)

1. Radial customization is hidden behind a toggle in Advanced.
2. The centre action is "the last list item", and its 10 pt / 28 pt zone is never explained.
3. Ring thickness, a visual setting, changes the hit zones.
4. "Unlink Trigger Key" is buried in a right-click menu.
5. Turning the preview off silently switches from apply-on-release to apply-live.
6. Minimum window size depends on preview padding, which is a theming value.
7. Snap zones are surprising. Landscape side edges never offer thirds.
8. More than 10 useful options are Terminal-only, including the deadzone and centring.
9. Permissions UX:
   - Permission entries are reset silently on every launch.
   - The notification prompt comes before the user has seen any value.
   - There is no status shown when Accessibility is lost.
10. The no-window state shows only a glyph, with no explanation.
11. Keybinds can be exported, but full settings cannot.
12. Many options only appear when another toggle is on, so they are hard to discover.
13. No accessibility labels and no Reduce Motion support.
14. Drag-snap is off by default. The macOS tiling conflict is only revealed after you turn it on.
