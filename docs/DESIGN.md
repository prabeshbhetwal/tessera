# Design

Tessera is a native SwiftUI macOS app. It has no palette of its own: colours, type and controls come from the system so the app matches whatever appearance and accent the user chose.

## Visual Theme

Quiet, native, System Settings-grade. A sidebar of coloured icon tiles on the left, grouped forms on the right, one header per pane that says what the pane controls. Panes, in ⌘1–9 order: General, Excluded Apps (Setup); Shortcuts, Cycles, Splits (Control); Displays, Ring, Overlay, Motion (Snapping); About on ⌘0. Spelling is en-AU throughout (Maximise, Centre, colour); command identifiers stay en-US.

The signature is the overlay: a vibrant material ring and a lifted preview frame, the one place Tessera looks like itself rather than like a form.

## Color

- Surfaces, text and separators: system semantic colours only (`windowBackground`, `.primary`, `.secondary`, `.separator`, `.quinary`).
- Accent: the user's system accent (`Color.accentColor`). Used for selection, focus rings, the live wedge in diagrams and the primary button. Never decoration.
- Pane icon tiles: one solid system colour per pane (gray, red, orange, green, blue, indigo, teal, mint), white symbol. This is the only place colour is used for identity.
- State: `.green` for granted permissions, `.orange` for warnings. Always paired with a symbol and text.

## Typography

System font (SF Pro) throughout. One family.

| Role | Style |
|---|---|
| Onboarding title | `.largeTitle` bold / `.title` bold |
| Pane header | `.title2` semibold |
| Body, controls | `.body` |
| Captions under controls | `.caption`, `.secondary` |
| Key names, sizes, counts | `.monospaced` or `.monospacedDigit()` |
| Keycaps | `.callout` rounded medium |

## Components

- `PaneHeader`: icon tile, pane title, one-sentence purpose. Top of every pane except About.
- `PaneIcon`: 20 pt (sidebar) or 40 pt (header) rounded tile, continuous corners, solid tint, white SF Symbol.
- `KeycapRow` / `Keycap`: modifier and key names drawn as keycaps; used for the trigger chord.
- `RecorderField`: shared focusable field for chord and hotkey recording. Space or Return records, Delete clears, Esc cancels.
- `SliderRow`: labelled slider with its value right-aligned in monospaced digits.
- `Caption`: secondary explanatory text under a control.
- `ResetSection`: trailing "Restore Defaults" button, last section of each pane, with an optional line saying what is kept. It is the only reset verb in the app.
- `RingDiagram`: the ring drawn with the overlay's own geometry (`RingLayer` paths). In the Ring pane it is the wedge picker: click or ← → to focus a wedge, one Picker below edits it. The Overlay pane's sample reuses it with the right-half wedge lit.
- Overlay (on screen): the ring is a vibrant `NSVisualEffectView` (`.hudWindow`, behind-window blending) cut to the wedges, with a theme tint, hairline edges, white glyphs and the accent wedge on top. Grid lines and the "from" outline carry a dark halo so they read on light wallpapers. The HUD is the same material in a capsule.
- Diagrams (`MiniGrid`, `ZoneDiagram`, `PreviewSample`, `FlickDemo`): `Canvas` drawings on a `.quinary` rounded panel, accent for the live element.

## Layout

- Settings: `NavigationSplitView` with a fixed 200 pt sidebar that can't collapse. The window is a fixed 820 × 720 pt (smaller only on a screen that can't fit it): never resized, zoomed or full screen. It remembers its position.
- Explanations go in section footers (`Footer`), under the rounded group, never as rows inside it. Inline captions are only for live validation (a name already taken, a hotkey conflict).
- Sliders never show tick marks; `SliderRow` rounds to its step in the binding.
- Appearance (General): Match System, Light or Dark for Tessera's own windows, chosen from window thumbnails.
- Forms: `.formStyle(.grouped)`; one `Section` per idea, sections in order of how often they are changed.
- Onboarding: fixed 600 × 500. Centred hero (demo or icon tile), title, 440 pt body column, step controls, footer with step dots and buttons.
- Spacing scale: 4, 8, 12, 16, 20, 24, 36.

## Customisation rule

Every behaviour the user can see has its own switch, and switches never change each other.
- Ring pane, Gestures: directions, pointing, click to span, scroll to change columns. A caption says what the current combination does.
- Ring pane, Appearance: show the ring, wedge icons (Layout pictures, Arrows, None), dashed boundary, frosted background, grid lines while picking a column. Hiding the ring keeps every gesture working.
- Ring pane, Colours: ring, tint, lines and icons, highlighted wedge, grid. A setting lives where the user looks for it: ring colours are in the Ring pane, and also in Overlay with the rest of the theme.
- Overlay pane: theme, every colour (ring, lines and icons, highlight, snap preview, grid, label, label text, outline, dimming); label parts (size, slot); dimming and the "from" outline as two switches.
- General: Appearance; Menu bar (show, icon, and which items: status line, Snap Front Window, Columns, Shortcuts…, Undo; Settings… and Quit always); Messages (on/off, position, duration).
- Shortcuts: a master hotkeys switch above the per-hotkey switches.
- Theme colours are edited through `SettingsModel.editTheme` / `themeColor`: a built-in theme is copied to "Custom" first and never changed itself.
A new setting only needs a default value in `TesseraSettings` (or a nested struct, or `Theme`): `SettingsMigration` fills missing keys in older files, including inside each custom theme.

## Motion

Follows Reduce Motion. Animations are the onboarding flick demo (paused under Reduce Motion), permission symbol replacement, the overlay's own morph and brief Ring selection/shortcut confirmation fades. No page transitions.

## Ring feedback

The icon-only direction palette was approved on 5 October 2026. Preserve this visual direction in follow-up work unless a new design is requested.

- The Ring is an icon-only direction palette. Window-layout glyphs share one optical aspect ratio and stroke treatment, without an outer band, tile backgrounds, repeated labels or a centre card. `RingGeometry` shares the icon silhouettes between the live overlay, material mask and Settings diagram; configured gesture angles and thresholds stay unchanged.
- Inactive destination fills are subdued; the selected destination gains the accent and a stronger outline. The centre is a tiny origin marker. During grid selection, the other icons recede and one unframed display glyph shows the span or portrait rows.
- A stationary two-line caption names the selected action or columns and explains release, Return and Escape. It stays readable while the dial recedes in grid mode and remains within the originating display's bounds.
- Initial state invites selection; returning to the centre after moving explains cancellation. A stationary tap advertises tiling only when that behaviour is enabled and the gesture is still eligible.
- Successful hotkeys show a compact material receipt with a single layout glyph (or checkmark) and the completed action. Failures use the existing message path. Rapid hotkeys cannot display an older completion over a newer command; opening the interactive Ring clears the receipt.
- `Ring → Action name and input hints` controls the caption. `General → Show messages`, position and duration control shortcut receipts. `Overlay → Preview Shortcut` previews the receipt without moving a window.
