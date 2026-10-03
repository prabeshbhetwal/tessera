# Tessera: Milestone 1 design spec

- **Date:** 2026-10-03
- **Status:** awaiting review
- **Scope:** Milestone 1 of 5. This milestone covers the engine, the radial menu with flick + point, and display profiles.

Background research, kept as reference only:
- `docs/loop-research-2026-10-03.md`
- `docs/loop-behaviour-teardown.md`
- `docs/loop-technical-mechanics.md`

---

## 1. Purpose

Tessera is a macOS window manager. You hold a trigger, move the cursor, and windows snap into place.

What makes it different: **every display gets its own grid, worked out from that display's usable size.**
- On a 14" MacBook you get halves and quarters.
- On a 49" 32:9 monitor you get 4–6 equal columns.
- Any other display gets a sensible grid from the same rule.

Tessera adapts on its own when you dock or undock.

### Who it is for
1. The author's daily driver: a 14" MacBook Pro plus a Samsung CHG90 49" (3840×1080) on a dock.
2. A portfolio piece, so code quality, tests and docs matter.
3. A possible public product later. Build it as if it will ship. Do not ship it in this milestone.

### Success criteria for Milestone 1
1. Undocked, holding the trigger and flicking or pointing snaps the frontmost window to halves or quarters on the MacBook.
2. Docked to the CHG90, the same gesture snaps windows into 5 columns by default. Scrolling while holding changes this to 3–6, and the choice is remembered for that monitor.
3. Click-to-span places one window across several adjacent columns.
4. Dock and undock while Tessera is running: no crash, and each display loads its saved profile.
5. A frozen app (`kill -STOP`) never freezes Tessera for more than 0.3 s.
7. The preview shows all four layers: thumbnail (when permitted), size and slot label, neighbour dimming with a "from" outline, and the spring morph. Each layer can be switched off.
8. Settings round-trip through export and import with no loss, and every tunable value in this spec is editable in the UI.
6. All pure-logic unit tests pass in CI.

### Non-goals (later milestones)
- **M2:** keyboard shortcuts and cycles.
- **M3:** drag-to-snap.
- **M4:** saved multi-window layouts and auto-restore on dock.
- **M5:** moving windows between Spaces.
- **Later:** trackpad gestures, zone editor, updater, iCloud sync.

---

## 2. Constraints

### Legal
Loop is GPL-3.0. We reuse ideas, behaviour and Apple API knowledge, but never Loop code.
- The `loop/` clone is reference only. It is gitignored and never imported.
- No Loop name or artwork.

### Platform and language
- macOS 15 Sequoia or later.
- Swift 6 language mode with **complete** strict concurrency checking.

### Dependencies
None in Milestone 1. Sparkle is added when we publish.

### Private APIs
Allowed where needed, with these rules:
- Load them only through `dlsym`, wrapped in an optional-returning helper.
- A missing symbol turns the feature off. It must never crash the app.
- Never use `@_silgen_name`.

### Code style
- Files stay under 500 lines.
- No force-unwraps or `try!` on system calls.

---

## 3. Display profiles and the sizing rule (GridKit)

### 3.1 Inputs
For each display:
- The **usable frame in points**: `NSScreen.visibleFrame` (this already excludes the menu bar and Dock and accounts for Retina scaling). The sizing rule uses it **before** padding, so padding never costs a column; padding is applied when frames are computed.
- The **whole screen frame** (`NSScreen.frame`) is used only to hit-test the cursor, so the menu bar and Dock strips are never dead zones.
- Its **stable identity**: vendor + model + serial, from `CGDisplayVendorNumber`, `CGDisplayModelNumber` and `CGDisplaySerialNumber`. If the serial is 0, fall back to `CGDisplayCreateUUIDFromDisplayID`.

### 3.2 Tunable constants

| Name | Default | Meaning |
|---|---|---|
| `idealColumnWidth` | 768 pt | Sets the default column count |
| `minColumnWidth` | 640 pt | Narrowest allowed column. Sets the maximum count. |
| `maxColumnWidth` | 1280 pt | Widest comfortable column. Sets the minimum count. |
| `minRowHeight` | 440 pt | Sets the maximum row count |
| `maxColumns` | 8 | Hard cap |

### 3.3 Rule
Let `W` be the usable width and `H` the usable height of a **landscape** display, where W ≥ H.

```
minCols     = max(1, ceil(W / maxColumnWidth))
maxCols     = clamp(floor(W / minColumnWidth), minCols, maxColumns)
defaultCols = clamp(round_half_even(W / idealColumnWidth), minCols, maxCols)
maxRows     = max(1, floor(H / minRowHeight))
```

**Portrait displays** (H > W) use the same rule with W and H swapped. The result describes **rows** instead of columns.

### 3.4 Required fixtures (unit tests must match exactly)

| Display | Usable W×H (pt) | minCols | maxCols | defaultCols | maxRows |
|---|---|---|---|---|---|
| MacBook Air 13" | 1470×923 | 2 | 2 | 2 | 2 |
| MacBook Pro 14" | 1512×949 | 2 | 2 | 2 | 2 |
| MacBook Pro 16" | 1728×1084 | 2 | 2 | 2 | 2 |
| 24" 1080p | 1920×1047 | 2 | 3 | 2 | 2 |
| 27" 1440p / 5K | 2560×1407 | 2 | 4 | 3 | 3 |
| 34" ultrawide | 3440×1407 | 3 | 5 | 4 | 3 |
| CHG90 49" | 3840×1047 | 3 | 6 | 5 | 2 |
| 57" dual-4K | 7680×2127 | 6 | 8 | 8 | 4 |
| 27" portrait | 1440×2527 | 2 rows | 3 rows | 3 rows | n/a |

The 24" default of 2 relies on rounding 2.5 half-to-even. That is intentional.

### 3.5 Profile
A **DisplayProfile** stores:
- `displayID`
- `columns`, which the user can change within `minCols...maxCols`
- `gap`: space between windows, default 8 pt
- `padding`: space at the screen edges, default 8 pt
- `isUserOverride`

Rules for saving:
- Auto-computed profiles are not persisted. Only user overrides are, in `SettingsStore` (see 6.4).
- "Reset to auto" deletes the override.

### 3.6 Geometry
- **Cells:** column `c` (0-based) has x = `usable.minX + c * (W / columns)`.
- **Spans:** a span is an inclusive range of columns plus a vertical band (`full`, `top`, `bottom`). Its frame is the union of its cells.
- **Gaps:** each window edge that does not touch the usable frame is inset by `gap / 2`. Adjacent windows therefore end up exactly one gap apart.
- **Coordinates:**
  - AX uses top-left coordinates relative to `NSScreen.screens[0]`. AppKit uses bottom-left.
  - All conversion goes through one function, `CoordinateSpace.toAX(_:)`, which is unit-tested with multi-display arrangements: MacBook left of the CHG90, CHG90 above the MacBook, and a portrait monitor on the right.

### 3.7 Rows in Milestone 1
- Point mode offers three vertical bands: full height, top half, bottom half.
- `maxRows` is computed and stored. Using rows beyond 2 is deferred.

---

## 4. Interaction: flick + point (SelectionEngine)

### 4.1 Trigger
- **Default:** Left Control + Left Option + Left Command, held together. The user can change it in Settings.
- **Open:** when every key in the chord is down and the frontmost app is not excluded.
- **Apply:** when any chord key is released.
- **Cancel:** Esc.
- **Other keys:** a non-modifier key pressed while the chord is held cancels the menu and **passes the key through**, so other apps' `⌃⌥⌘+key` shortcuts keep working.

### 4.2 Zones
Distance `d` is measured from the cursor position at the moment the menu opened.

| Distance | Mode | Selection |
|---|---|---|
| d < 10 pt | dead zone | none |
| 10 ≤ d < 90 pt | **flick** | the wedge chosen by angle |
| d ≥ 90 pt | **point** | the cell or span under the cursor |

Both boundaries are user-tunable in Settings → Ring, with a diagram.

### 4.3 Flick wedges
Eight wedges of 45°. The first is centred straight up, and the rest run clockwise. Each wedge is editable in Settings.

Defaults:

| Up | Up-right | Right | Down-right | Down | Down-left | Left | Up-left |
|---|---|---|---|---|---|---|---|
| Maximize | Top-right quarter | Right half | Bottom-right quarter | Center (keep size) | Bottom-left quarter | Left half | Top-left quarter |

**Halves and quarters are relative to the display, not the grid.** They are the same on every screen.

### 4.4 Point mode
1. The grid overlay appears on **the display under the cursor**. That makes it the target display, so moving a window to another display is free in M1.
2. The column under the cursor is selected.
3. The vertical position within the usable height picks the band:
   - top 30% → `top`
   - middle 40% → `full`
   - bottom 30% → `bottom`
4. **Left-click while holding** anchors a span. The selection then becomes the bounding span from the anchor cell to the current cell, using the union of their bands. A second click moves the anchor.
5. **Scroll while holding** changes `columns` by ±1 within range, updates the overlay live, and saves an override.

### 4.5 Feedback
- **Ring:** a ring at the open point with the active wedge highlighted.
- **Grid overlay:** grid lines in point mode.
- **Preview:** the rich preview described in 4.6.
- **No target window:** a short HUD reading "No window to move".
- **Reduce Motion:** when it is on, there are no animations.

### 4.6 Preview
Loop's preview is a blurred, tinted rectangle. Ours has four layers, and each one can be switched on or off in Settings → Preview.

1. **Live window thumbnail**
   - When the session opens, take a **single** snapshot of the target window with ScreenCaptureKit (`SCScreenshotManager.captureImage` with `SCContentFilter(desktopIndependentWindow:)`).
   - Draw that snapshot scaled into the target frame with aspect-fill, clipped to the preview's corner radius, at the user-set opacity.
   - Do not capture again on every mouse move.
   - This needs Screen Recording permission, which is **optional**. Without it, or if the capture fails or takes more than 150 ms, fall back to the styled rectangle without a thumbnail.
2. **Size and slot label**
   - A centred pill showing the final frame in points and the slot, e.g. `1280 × 1047 · cols 2–3 · top`, or `Left half` for flicks.
   - It shows the frame after gaps and after the app's size constraints, where those are known from the last read-back for that window.
3. **Neighbour awareness**
   - When the session opens, snapshot the frames of other on-screen windows with `CGWindowListCopyWindowInfo` (bounds only; this needs no permission).
   - Windows that the new frame would cover by more than 20% are dimmed with an overlay.
   - The target window's current frame is drawn as a dashed "from" outline.
4. **Smooth morph**
   - The preview frame animates between selections with a critically damped spring. Response is 0.18 s by default and can be set from 0.08 to 0.4 s.
   - The animation runs in Core Animation on the overlay layer, so no Accessibility calls happen per frame.
   - Under Reduce Motion, or when the response is set to 0, the preview jumps instead.

`PreviewModel` is pure (it lives in TesseraCore). It takes the selection, frames, neighbour frames and settings, and returns the layers to draw: the frame, the label text, the dim rectangles and the "from" outline. It is unit-tested. The panel only renders what it receives.

---

## 5. Architecture

### 5.1 Packages and folders
- `Packages/TesseraCore` is a local Swift package with no AppKit. It contains:
  - `GridKit`
  - `SelectionEngine`
  - `TriggerMachine`
  - `PreviewModel` (pure layer model for the preview, see 4.6)
  - `SettingsStore` (versioned Codable `TesseraSettings` plus file I/O behind a protocol, see 6.4)

  It is tested with `swift test`.
- `Tessera/` is the macOS app target. It contains:
  - `App/`: the menu bar, settings window and onboarding
  - `Services/`: `InputService`, `DisplayService`, `WindowService`
  - `Overlay/`: the ring, grid and preview panels
  - `SPI/`: the `dlsym` loader

### 5.2 Responsibilities

| Unit | Isolation | Responsibility |
|---|---|---|
| GridKit | pure | Sizing rule, profiles, cells and spans to frames, gaps, coordinate conversion |
| SelectionEngine | pure | Takes origin, cursor, display profiles and ring config. Returns `Selection` (`.none`, `.wedge(Action)` or `.span(displayID, cols, band)`). |
| TriggerMachine | pure | Takes key, flag, click, scroll and Esc events. Emits `open`, `update`, `apply`, `cancel` and `passThrough`. |
| PreviewModel | pure | Takes selection, frames, neighbour frames and settings. Returns the preview layers: frame, label, dim rectangles and "from" outline. |
| SettingsStore | actor | Loads, migrates and saves `settings.json`, handles import and export, keeps an in-memory cache, and pushes changes to services. Never read on hot paths. |
| ThumbnailService | actor | Takes one ScreenCaptureKit snapshot per session, with a 150 ms budget. Returns nil when permission is missing or the capture fails. |
| InputService | dedicated thread | Owns the `CGEventTap` (active for keys, clicks and scroll while open; passive for mouse moves). Its callback copies each event into a Sendable value and never blocks. Re-enables the tap on timeout, with backoff (more than 5 restarts in 2 s means a 2 s pause). |
| DisplayService | main actor | Lists screens and stable IDs. Listens for `didChangeScreenParametersNotification`. Publishes `[DisplayContext]`. |
| WindowService | serial actor | Handles every Accessibility call (see 5.4). |
| Coordinator | main actor | Connects the units above. Owns the session state for one trigger press. |
| OverlayUI | main actor | One reusable non-activating `NSPanel` per display, at `.screenSaver` level, with `ignoresMouseEvents`. Ring and grid are drawn with `CAShapeLayer`; no SwiftUI on the hot path. |
| SPI | n/a | `_AXUIElementGetWindow`. Optional; Milestone 1 works without it. |

### 5.3 Data flow
1. **Tap** → InputService → `InputEvent` (Sendable) → main actor → TriggerMachine.
2. **`open`:** the Coordinator snapshots the displays and profiles, asks WindowService for the target window (frontmost), and shows the overlay.
3. **Mouse move:** SelectionEngine → `Selection` → GridKit frame → OverlayUI preview.
4. **`apply`:** `WindowService.apply(frame, to: window)` → push the previous frame onto the undo stack → hide the overlay.

### 5.4 WindowService rules
- Apply `AXUIElementSetMessagingTimeout(appElement, 0.3)` to every application element.
- **Same display:** set position, then size. **Different display:** set size, then position, then size.
- If the app has `AXEnhancedUserInterface` on, turn it off, apply the frame, then turn it back on.
- Read the frame back **once** at the end. If the size is constrained, re-anchor the actual size to the edges that were targeted.
- Undo stack: the last 20 frames per window. "Undo last move" is available from the menu bar.
- A per-bundle quirk table holds known workarounds. It starts empty and grows from the manual test matrix.

---

## 6. Settings and onboarding

Settings have no hidden or Terminal-only options. Turning one setting on never silently changes a different behaviour.

### 6.1 Settings panes
- **General:** trigger chord recorder, launch at login (`SMAppService.mainApp`), show menu bar icon.
- **Displays:** each connected display with a live mini-grid. For each display: columns (stepper within range), gap, padding, and "Reset to auto". An **Advanced** section shows the 5 sizing constants.
- **Ring:** wedge assignments, dead zone and flick distance sliders, and a zone diagram.
- **Preview:** the 4 layers, each with its own options (see 6.4). Includes a live sample.
- **Appearance:** themes (built-in and custom), ring style, accent colour. Follows the system Reduce Motion setting.
- **Excluded Apps:** list.
- **About:** version and licence.

### 6.2 Onboarding
1. **Welcome:** a short clip of flick + point.
2. **Accessibility:** a "Grant" button that calls `AXIsProcessTrustedWithOptions(prompt)`. A live checkmark watches the `com.apple.accessibility.api` distributed notification and re-checks 250 ms after it fires. A "Fix permission" button (`tccutil reset Accessibility <bundle>`) appears only if the permission is still not granted after 10 s.
3. **Window thumbnails (optional):** explains what Screen Recording is used for and offers "Enable" or "Skip". If skipped, the preview uses the rectangle style. The user can enable it later from Settings → Preview.
4. **Try it:** a demo window to snap.

### 6.4 Customisation
Tessera must be heavily customisable. These rules apply:

1. **Every tunable value is in Settings**, with a sensible default and a "Reset" button per section. That covers every number in this spec: zone distances, sizing constants, gaps, padding, band split, spring response, opacities, radii and thicknesses.
2. **One settings model.**
   - `TesseraSettings` is a Codable struct with a `schemaVersion` and an explicit migration step per version.
   - It is stored at `~/Library/Application Support/Tessera/settings.json`.
   - Per-display profile overrides live inside it.
   - It is loaded once and cached in memory. Changes are pushed to services, never read on hot paths.
3. **Import and export** of all settings as one `.json` file, from Settings → General. This is Loop's top unmet request.
4. **Themes**
   - Three built-in presets: *Default*, *Minimal* (outline only, no blur, no thumbnail) and *Glass* (blur, thumbnail, Liquid Glass on macOS 26+).
   - The user can save their current look as a custom theme.
   - A theme covers the ring, the preview and the accent only, never behaviour.
5. **Customisable areas**

   | Area | Options |
   |---|---|
   | Trigger | Any modifier chord or key, plus an optional trigger delay |
   | Ring | Size, thickness, colours, wedge actions (the 8 wedges can map to any action), dead zone, flick distance |
   | Grid | Sizing constants; per-display columns, gap and padding; band split (default 30/40/30) |
   | Preview | Each of the 4 layers on or off, opacity, border width and colour, corner radius (fixed or the window's own), label position, dim strength, spring response |
   | Excluded apps | Per-app list |

6. **No setting silently changes a different behaviour.** Settings that depend on another setting are shown disabled, with a note explaining why, never hidden.

### 6.3 App shell
- `LSUIElement = YES` (no Dock icon).
- The app switches to `.regular` only while Settings is open.
- Single instance, enforced by checking `NSRunningApplication` for our bundle ID.
- **Bundle ID:** `com.prabeshbhetwal.Tessera` (placeholder).

---

## 7. Error handling

| Failure | Behaviour |
|---|---|
| Accessibility not granted or revoked | The menu bar icon turns amber. The trigger is inactive. The menu shows "Permission needed" and reopens onboarding step 2. |
| Event tap disabled by the system | Re-enabled with the backoff described in 5.2 and logged. |
| AX call times out or fails | No change to the window. HUD reads "Can't move this window". The failure is logged with the bundle ID. |
| No frontmost window | HUD reads "No window to move". |
| A display is unplugged mid-session | Cancel the session and rebuild the displays. |
| SPI symbol missing | The feature degrades to its public-API path. Logged once. |
| `settings.json` is corrupt or from a newer schema | Rename it to `settings.corrupt-<timestamp>.json`, start from defaults, tell the user once, and log it. User data is never deleted silently. |
| Thumbnail capture is denied, slow or fails | Fall back to the rectangle preview for that session. No HUD. |
| An imported settings file is invalid | Reject the whole import, show the first validation error, and leave current settings untouched. |

Logging uses `os.Logger` with subsystem `com.prabeshbhetwal.Tessera` and one category per service.

---

## 8. Testing

### 8.1 Unit tests (Swift Testing, `swift test` in TesseraCore)
- **GridKit:**
  - Every fixture row in 3.4.
  - Gap maths.
  - Spans.
  - Portrait displays.
  - `CoordinateSpace` with 3 multi-display arrangements.
- **SelectionEngine:**
  - Dead zone and flick boundaries, including the exact 10 pt and 90 pt edges.
  - The 8 wedge angles and their boundaries (22.5° and so on).
  - The 30/40/30 bands.
  - Span anchoring and re-anchoring.
  - Point mode on a second display.
- **TriggerMachine:**
  - Chord down/up in every order.
  - Partial release, Esc, and pass-through of another key.
  - Scroll.
  - Fast press–release–press sequences.
- **PreviewModel:**
  - Label text for flick and span selections.
  - The 20% dimming threshold.
  - The "from" outline.
  - Each layer turned off on its own.
- **SettingsStore:**
  - Migration from schema v1.
  - Export then import gives equal settings.
  - An invalid import is rejected without changes.
  - Round trip.
  - Same monitor matched after redocking.
  - Recovery from a corrupt file.

### 8.2 Manual matrix (before each tagged build)
- **Apps:** Safari, Chrome, VS Code, Finder, Terminal, Slack, Xcode, QuickTime (fixed aspect ratio), and a frozen app (`kill -STOP <pid>`).
- **Display states:** MacBook only, docked to the CHG90, and docking or undocking while running.

### 8.3 Performance budget

| Measure | Budget |
|---|---|
| SelectionEngine and GridKit per mouse move | < 2 ms |
| Apply | < 50 ms typical |
| Main thread blocked by a frozen app | < 0.3 s |

### 8.4 CI
GitHub Actions on a macOS runner, on every push:
- `swift test` for TesseraCore
- `xcodebuild test` for the app
- SwiftFormat lint

---

## 9. Repository
- The git repository root is `LoopAlternative/`.
- `.gitignore` covers `loop/`, `.build/`, `DerivedData/`, `xcuserdata/`, `.env*` and `.DS_Store`.
- `Package.resolved` **is** committed.
- Remote: a private GitHub repo, created when the user decides.

---

## 10. Open items (do not block Milestone 1)
- Final bundle ID and developer team, decided before the first signed build.
- Whether to use the native macOS 15 `_zoom*` menu path for halves to get smoother animation. Evaluate in M2.
- Use of rows beyond 2 in point mode. Evaluate after daily use.
