# Design

Tessera is a native SwiftUI macOS app. It has no palette of its own: colours, type and controls come from the system so the app matches whatever appearance and accent the user chose.

## Visual Theme

Quiet, native, System Settings-grade. A sidebar of coloured icon tiles on the left, grouped forms on the right, one header per pane that says what the pane controls. The sidebar is grouped by task. Panes, in sidebar order: General; Controls (Ring, Shortcuts, Cycles, Excluded Apps); Windows (Displays, Splits); Look (Appearance, Motion); then Updates and About under no title. ⌘1–9 select them in that order, skipping Updates (rarely opened, so adding it moved no other pane's digit): General 1, Ring 2, Shortcuts 3, Cycles 4, Excluded Apps 5, Displays 6, Splits 7, Appearance 8, Motion 9; ⌘0 selects About. Appearance's internal key is still `overlay`, so search anchors and saved navigation keep working. Spelling is en-AU throughout (Maximise, Centre, colour); command identifiers stay en-US.

The signature is the overlay: a vibrant material ring and a lifted preview frame, the one place Tessera looks like itself rather than like a form.

## Color

- Surfaces, text and separators: system semantic colours only (`windowBackground`, `.primary`, `.secondary`, `.separator`, `.quinary`).
- Accent: the user's system accent (`Color.accentColor`). Used for selection, focus rings, the live wedge in diagrams and the primary button. Never decoration.
- Pane icon tiles: one solid system colour per pane, none shared (General gray, Updates cyan, Excluded Apps red, Shortcuts orange, Cycles green, Splits purple, Displays blue, Ring indigo, Appearance teal, Motion mint, About pink), white symbol. This is the only place colour is used for identity.
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

- `PaneHeader`: icon tile, pane title, one line of purpose (at most 8 plain words). Top of every pane except About.
- `PaneIcon`: 20 pt (sidebar), 24 pt (icon-only sidebar) or 40 pt (header) rounded tile, continuous corners, solid tint, white SF Symbol.
- `KeycapRow` / `Keycap`: modifier and key names drawn as keycaps; used for the trigger chord.
- `RecorderField`: shared focusable field for chord and hotkey recording. Space or Return records, Delete clears, Esc cancels.
- `SliderRow`: labelled slider with its value right-aligned in monospaced digits.
- `Caption`: secondary explanatory text under a control.
- `InfoHeader` / `InfoButton` (`Tessera/UI/InfoButton.swift`): a section header with a small borderless ⓘ at its trailing end. Click or Space opens a popover of 1–3 short sentences. VoiceOver label "About <section>". Not every section gets one; only those that need explaining.
- `ResetSection`: trailing "Restore Defaults" button, last section of each pane, with an optional line saying what is kept. It is the only reset verb in the app.
- Menu bar glyphs (`MenuBarGlyph`): Tessera's own template pictures, never SF Symbols, in the app icon's flat-tile language: Tiles (the app icon's 3×2 grid, default), Badge (the app icon as a solid card with the tiles cut out), Slot (3×2 with one open tile), Mosaic, Ring (eight wedges round a centre dot), Split, Columns, Quarters. Drawn on an 18 × 18 pt canvas with every tile edge on a whole point and 2 pt gaps, so they stay sharp on 1x displays. States are cut out of the chosen glyph, never swapped for another picture: a pause disc at the bottom-right while hotkeys are paused, a dot at the top-right while an update waits. Only missing Accessibility replaces the glyph, with the orange warning triangle. The General pane's picker shows the same images.
- `RingDiagram`: the ring drawn with the overlay's own geometry (`RingLayer` paths). In the Ring pane it is the wedge picker: click or ← → to focus a wedge, one Picker below edits it. A soft neutral plate follows the pointer (or keyboard focus) around the ring on a spring (response 0.32, damping 0.78), the short way round; the tile under it grows up to 8 % and brightens, so neighbours swell as it passes. The Appearance pane's sample reuses it with the right-half wedge lit.
- Overlay (on screen): the ring is a vibrant `NSVisualEffectView` (`.hudWindow`, behind-window blending) cut to the wedges, with a theme tint, hairline edges, white glyphs and the accent wedge on top. Grid lines and the "from" outline carry a dark halo so they read on light wallpapers. The HUD is the same material in a capsule.
- Coach (on screen): a card beside the windows an event was about, on a dim with those windows cut out. The card is the one overlay that takes clicks; the dim stays click-through. The dim uses the Dimming colour (Appearance › Preview and label colours) and Dim strength (Appearance › Around the preview). The spotlight outline and the "try it" seam use the theme accent, deliberately: they mark the live element. Reduce Motion stops the seam's pulse; the card and dim keep their 0.2 s fades, because a cross-fade isn't motion. With General › Tips › Dim the screen behind tips off, every card shows without the dim, except that a "try it" step keeps its pulsing seam on a clear layer.
- Diagrams (`MiniGrid`, `ZoneDiagram`, `PreviewSample`, `FlickDemo`): `Canvas` drawings on a `.quinary` rounded panel, accent for the live element.

## Layout

- Settings: `NavigationSplitView` whose sidebar is never hidden. Full, it is 230 pt by default, never narrower than 220 pt so the search field shows its whole placeholder, at most 280 pt. The title-bar sidebar button (⌃⌘S) narrows it to icons only, 140 pt, as narrow as the title bar's window buttons and toggle allow (a search button over the pane icons, each named in its tooltip) and back; the choice is remembered. Dragging the divider shut also lands on icons only. Switching sets the sidebar item's width range in AppKit (`SidebarWidth`): SwiftUI reads the column width only when it builds the split, and rebuilding it would reset the detail pane. ⌘F or the search button widens it and focuses search. The window is a fixed 820 × 720 pt (smaller only on a screen that can't fit it): never resized, zoomed or full screen. It remembers its position.
- Text is short. A pane header line is at most 8 plain words. Section footers (`Footer`, under the rounded group, never rows inside it) are only for warnings and live state (hotkeys paused, a login item that needs approval, a missing permission). Explanations go in an ⓘ (`InfoHeader`) at the trailing end of the section header. Inline captions are only for live validation (a name already taken, a hotkey conflict). A button whose effect isn't obvious from its label may carry a `.help` tooltip.
- Put an action on the thing it acts on: About's copy icon (`doc.on.doc`, a tick for about 2 s after copying) sits beside the version line rather than in a separate button.
- Sliders never show tick marks; `SliderRow` rounds to its step in the binding.
- Light or dark (General › App): Match System, Light or Dark for Tessera's own windows, chosen from window thumbnails.
- Forms: `.formStyle(.grouped)`; one `Section` per idea, sections in order of how often they are changed. Exception: a pane whose main job is a status and one action (Updates) puts that first, as System Settings › Software Update does.
- Onboarding: fixed 600 × 500. Centred hero (demo or icon tile), title, 440 pt body column, step controls, footer with step dots and buttons.
- Spacing scale: 4, 8, 12, 16, 20, 24, 36.

## Customisation rule

Every behaviour the user can see has its own switch, and switches never change each other.
- Ring pane, in order: Trigger (the chord that opens the ring); Gestures (directions, pointing, click to span, scroll to change columns; a footer appears only when tap-in-place tiles windows or when every gesture is off); Directions (the wedge picker); Size and zones (radius, thickness, point threshold, and the top and bottom bands: while pointing, they decide where a window snaps to half height). Behaviour only. Restore Defaults resets all of these plus the trigger, and leaves the ring's look alone. Bands are ring settings, not display settings.
- Every setting has exactly one home. The ring's look and colours live in Appearance only; the Ring pane has no Appearance or Colours section.
- Appearance pane, in order: the sample with Preview Shortcut and Show on Screen; Theme; Ring (show the ring, action name and input hints, layout icons (Layout pictures or Arrows; always shown), dashed circle where pointing begins, frosted background; hiding the ring keeps every gesture working); Grid and hints (grid lines while picking a column, numbered columns, the "click to add columns" hint, Show the hint again); Ring colours (ring, tint, lines and icons, highlighted wedge, grid); Preview and label colours (snap preview, label, label text, outline, dimming); Preview (fill style, opacity, border, corners) as one section; Label (parts: size, slot); Around the preview (dimming and the "from" outline as two switches); Restore Defaults. Restore Defaults keeps saved themes and also resets the ring look switches.
- General, in order: App (launch at login, light or dark, Understand searches with Apple Intelligence); Menu bar (show, icon, show each item's shortcut); Menu items (status line, What Just Happened?, Snap Front Window, Columns, Shortcuts…, Undo, Check for Updates…; Settings… and Quit always); Messages (on/off, position, duration); Tips (tips on their own, dim behind tips, Show Tips Again); Advanced (settings export and import, command-line tool; collapsed); Restore Defaults. Restore Defaults does not touch the trigger (that is Ring's). While hotkeys are paused the menu shows an enabled "Hotkeys Off" row that opens Settings › Shortcuts, the icon carries its pause badge and the Menu bar footer says why.
- Updates: Last checked and Check Now first; then Automatic updates (check automatically, frequency, download and install automatically, betas); Restore Defaults. While the app on disk is not the build that is running (rebuilt or replaced while open), checks are refused and a warning row under Last checked says to reopen Tessera. The one Settings home for updates: About shows the version (with a copy icon beside it) and links only, and the menu bar's Check for Updates… is the other way to check.
- Splits: Learning, then Learned splits as one row per display (display icon, name, “Not connected” when it is, count, Manage…) and Forget All…; “Nothing learned yet” is the section footer. The pane stays short with any number of displays. Manage… opens a 540 × 460 sheet for that display: search by app, rows with up to four app icons, names and date, a ⊖ per row (Delete forgets the selection; more than one asks first; selection drops rows the search hides), Forget All on This Display… (confirmed), Done (Return), Esc closes. The sheet closes when its display has no splits left.
- Shortcuts: a master hotkeys switch above the per-hotkey switches.
- Theme colours are edited through `SettingsModel.editTheme` / `themeColor`: a built-in theme is copied to "Custom" first and never changed itself.
A new setting only needs a default value in `TesseraSettings` (or a nested struct, or `Theme`): `SettingsMigration` fills missing keys in older files, including inside each custom theme.

## Motion

Follows Reduce Motion. Animations are the onboarding flick demo (paused under Reduce Motion), permission symbol replacement, the About copy icon turning into a tick (instant under Reduce Motion), the Ring pane picker's gliding hover plate (instant under Reduce Motion), the overlay's own morph, brief Ring selection/shortcut confirmation fades, the coach's 0.2 s fades (kept under Reduce Motion) and its pulsing "try it" seam (still under Reduce Motion). No page transitions.

## Ring feedback

The icon-only direction palette was approved on 5 October 2026. Preserve this visual direction in follow-up work unless a new design is requested.

- The Ring is an icon-only direction palette. Window-layout glyphs share one optical aspect ratio and stroke treatment, without an outer band, tile backgrounds, repeated labels or a centre card. `RingGeometry` shares the icon silhouettes between the live overlay, material mask and Settings diagram; configured gesture angles and thresholds stay unchanged.
- Inactive destination fills are subdued; the selected destination gains the accent and a stronger outline. The centre is a tiny origin marker. During grid selection, the other icons recede and one unframed display glyph shows the span or portrait rows.
- A stationary two-line caption names the selected action or columns and explains release, Return and Escape. It stays readable while the dial recedes in grid mode and remains within the originating display's bounds.
- Initial state invites selection; returning to the centre after moving explains cancellation. A stationary tap advertises tiling only when that behaviour is enabled and the gesture is still eligible.
- Successful hotkeys show a compact material receipt with a single layout glyph (or checkmark) and the completed action. Failures use the existing message path. Rapid hotkeys cannot display an older completion over a newer command; opening the interactive Ring clears the receipt.
- `Appearance → Ring → Action name and input hints` controls the caption. `General → Messages` (on/off, position, duration) controls shortcut receipts. `Appearance → Preview Shortcut` previews the receipt without moving a window.
