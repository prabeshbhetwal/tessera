# Product

## Register

product

## Users

Mac users who keep many windows open, often across a laptop screen and a large external display (14" MacBook plus a 49" 32:9 ultrawide is the reference setup). They are comfortable with keyboard shortcuts and want windows placed in one gesture without leaving the keyboard or picking up the mouse for long. Power users may script Tessera from the terminal, Shortcuts or AppleScript.

Context: the Settings window is opened rarely, to tune one thing, and closed. Onboarding is seen once, right after install, when the user wants to get to the first snap as fast as possible. Both run on macOS 15 and follow the system appearance (light or dark) and accent colour.

## Product Purpose

Tessera snaps the frontmost window into a grid that fits each display. Hold a trigger chord, flick for halves and quarters or point at a column, release. It exists because fixed-fraction snapping wastes ultrawide screens and because every surface (gesture, hotkey, CLI, URL, AppleScript, Shortcuts) should run the same commands. Success: a new user snaps a window within a minute of launch, and an experienced user never needs to open Settings to understand what a control does.

## Brand Personality

Precise, quiet, native. Tessera should feel like a part of macOS that Apple forgot to ship, not a third-party utility with its own visual language. Confident copy, no marketing tone, no exclamation marks.

## Anti-references

- Classic System Preferences toolbar tabs (a row of eight icon tabs across the top). Dated and hides where a setting lives.
- Loop's own look. Tessera is a clean-room implementation and must not read as a Loop clone.
- Electron-style settings: cards inside cards, huge paddings, custom controls that mimic the web.
- Permission screens that read like legal notices. Permissions are a two-line explanation and one button.

## Design Principles

1. Native first. Standard macOS controls, grouped forms, sidebar navigation, system fonts. Familiarity is the feature.
2. Show the setting. Every numeric control that shapes the overlay (ring zones, grid, preview) has a live diagram next to it.
3. Keyboard complete. Every control reachable with Tab, every pane with ⌘1 to ⌘8, every recorder operated with Space, Return, Delete and Esc.
4. Honest state. Permission and conflict states are always visible where they matter, never only in a dialog.
5. Nothing hidden. No Terminal-only defaults, and no setting silently changes another.

## Accessibility & Inclusion

Target WCAG AA contrast in light and dark mode using system semantic colours. Full VoiceOver labels and values on recorders, diagrams and reorderable rows. Reduce Motion is honoured by the overlay and by the onboarding demo. Nothing conveyed by colour alone (permission state also uses symbol and text).
