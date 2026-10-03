# Design

Tessera is a native SwiftUI macOS app. It has no palette of its own: colours, type and controls come from the system so the app matches whatever appearance and accent the user chose.

## Visual Theme

Quiet, native, System Settings-grade. A sidebar of coloured icon tiles on the left, grouped forms on the right, one header per pane that says what the pane controls.

## Color

- Surfaces, text and separators: system semantic colours only (`windowBackground`, `.primary`, `.secondary`, `.separator`, `.quinary`).
- Accent: the user's system accent (`Color.accentColor`). Used for selection, focus rings, the live wedge in diagrams and the primary button. Never decoration.
- Pane icon tiles: one solid system colour per pane (gray, orange, blue, indigo, teal, pink, green, red), white symbol. This is the only place colour is used for identity.
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
- `ResetSection`: trailing "Reset section" button, last section of each pane.
- Diagrams (`MiniGrid`, `ZoneDiagram`, `PreviewSample`, `FlickDemo`): `Canvas` drawings on a `.quinary` rounded panel, accent for the live element.

## Layout

- Settings: `NavigationSplitView`, sidebar 200 pt, detail min 560 pt. Window min 760 × 540, resizable.
- Forms: `.formStyle(.grouped)`; one `Section` per idea, sections in order of how often they are changed.
- Onboarding: fixed 600 × 500. Centred hero (demo or icon tile), title, 440 pt body column, step controls, footer with step dots and buttons.
- Spacing scale: 4, 8, 12, 16, 20, 24, 36.

## Motion

Follows Reduce Motion. The only animations are the onboarding flick demo (paused under Reduce Motion), permission symbol replacement and the overlay's own morph. No page transitions.
