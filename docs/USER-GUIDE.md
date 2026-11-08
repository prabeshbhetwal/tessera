# Tessera User Guide

Tessera snaps windows into a grid that fits each display. A 14" MacBook gets halves and quarters. A 49" ultrawide gets five columns. You hold a key chord, move the mouse, and let go.

This guide covers every feature, with examples. Jump to the part you need:

1. [Getting started](#1-getting-started)
2. [The ring: flick and point](#2-the-ring-flick-and-point)
3. [Columns and displays](#3-columns-and-displays)
4. [Hotkeys](#4-hotkeys)
5. [Cycles](#5-cycles)
6. [Tiling every window](#6-tiling-every-window)
7. [Learned splits](#7-learned-splits)
8. [Undo](#8-undo)
   - [8a. What Just Happened?](#8a-what-just-happened)
9. [The menu bar menu](#9-the-menu-bar-menu)
10. [Settings, pane by pane](#10-settings-pane-by-pane)
11. [Automation: command line, URLs, AppleScript, Shortcuts](#11-automation)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Getting started

**Requirements:** macOS 15 Sequoia or later.

### First launch

A short setup window walks you through five steps:

| Step | What it does |
|---|---|
| Snap windows with the ring | An animation of the gesture. |
| Allow Accessibility | **Required.** Tessera moves and resizes other apps' windows through macOS Accessibility. Nothing works until you allow it. Choose **Grant…** and turn Tessera on in System Settings. |
| Window snapshots | **Optional.** Screen Recording, used only for the *Window snapshot* preview style. Tessera takes one still picture per gesture and never records or saves anything. |
| Tiling that remembers | How Tile All Windows learns your layout, and how closing a window fills its space (see [Splits](#7-learned-splits)). |
| Try it | Practise the gesture on a real window. |

> **Accessibility still shows "Not granted"?** An older Tessera build may have left a stale entry. Choose **Fix permission** on that step to reset it, then grant again.

### Your first snap

1. Click a window in another app, such as Safari.
2. Hold the trigger: **Left Control + Left Option + Left Command** (⌃⌥⌘) by default.
3. Move the mouse a little to the right.
4. Let go. The window fills the right half of the screen.

---

## 2. The ring: flick and point

When you hold the trigger, a ring appears around the cursor. What you get depends on how far you move.

### Flick: a short move picks a layout

The ring has eight wedges. Move a little towards one and it lights up:

| Direction | Default layout |
|---|---|
| Up | Maximise |
| Up-right | Top-right quarter |
| Right | Right half |
| Down-right | Bottom-right quarter |
| Down | Centre |
| Down-left | Bottom-left quarter |
| Left | Left half |
| Up-left | Top-left quarter |

You can change what each direction does in **Settings › Ring › Directions**. The available layouts are: Maximise, Centre, the four halves and the four quarters.

### Point: a longer move picks a column

Keep moving past the ring, beyond the **point threshold** (90 pt by default). The ring gives way to your display's column grid, and the column under the cursor lights up.

- **Height bands:** with the cursor near the top of the screen (the top 30%), the window takes the top half of the column. Near the bottom 30%, it takes the bottom half. Anywhere in between, it takes the full height.
- **Span several columns:** click while pointing, then move to another column. The window spans every column between the two.
- **Change the column count:** scroll while holding the trigger. Tessera remembers the count for that display.

**Example: a 49" ultrawide with 5 columns.** Hold the trigger, move far left until column 1 lights up, click, then move to column 2. Let go. The window fills the two left-most columns, about 40% of the screen.

### Cancelling

Any of these cancels without moving the window:
- Let go in the ring's empty middle.
- Press **Esc**.
- Right-click.

### The preview

While you hold the trigger, Tessera shows where the window will land:
- a box in the target position (a tinted box, a snapshot of the window, or the app's icon; see [Overlay](#overlay))
- a label with the exact size and slot, for example "1280 × 1047 · cols 2–3 · top"
- dimming over the windows it will cover
- an optional dashed outline of where the window is now

### Tap to tile (off by default)

In **Settings › Ring › Gestures**, turn on **Press and release without moving to tile all windows**. Pressing and releasing the trigger without moving the mouse then runs [Tile All Windows](#6-tiling-every-window) on that display.

### Driving the ring with the keyboard

While the trigger is held, these keys control the ring:

| Key | Action |
|---|---|
| ← / → | Move one column |
| ⇧← / ⇧→ | Extend the span |
| ↑ / ↓ | Switch between the bottom, full and top bands |
| 1–9 | Jump to that column |
| = / − | One more or one fewer column |
| Tab / ⇧Tab | Next or previous display |
| Return | Apply and close |
| Esc | Cancel |

You can turn this off in **Settings › Shortcuts › Ring keyboard**.

---

## 3. Columns and displays

Each display gets its own grid, sized from its usable width. Tessera aims for columns about **768 pt** wide, and never narrower than 640 pt or wider than 1280 pt. There are at most 8 columns.

| Display | Usable width | Columns allowed | Default |
|---|---|---|---|
| 14" MacBook Pro | ~1512 pt | 2 | 2 |
| 49" 32:9 ultrawide (3840 × 1080) | 3840 pt | 3 to 6 | 5 |

A portrait display uses **rows** instead of columns, stacked top to bottom.

**Changing the count** (Tessera remembers it per display, even after you unplug and reconnect):
- scroll while holding the trigger
- **⌃⌥=** / **⌃⌥−**
- the menu bar's **Columns** submenu
- **Settings › Displays**

**Gap and padding:** the gap is the space between windows. Padding is the space at the screen edges. Both are 8 pt by default and can be set per display in **Settings › Displays**.

**Moving to another display:** **⌃⌥N** (next) and **⌃⌥P** (previous). The window keeps its relative column position on the new display. If it wasn't in a column, it is scaled to the same proportion of the screen.

---

## 4. Hotkeys

These work without the ring. You can rebind every one of them in **Settings › Shortcuts**.

| Hotkey | Action |
|---|---|
| ⌃⌥← | Cycle "left": left half → first column → first two columns |
| ⌃⌥→ | Cycle "right": right half → last column → last two columns |
| ⌃⌥↑ | Maximise |
| ⌃⌥↓ | Centre |
| ⌃⌥1 … ⌃⌥9 | Column 1 … 9 |
| ⌃⌥= / ⌃⌥− | One more / one fewer column |
| ⌃⌥N / ⌃⌥P | Move to the next / previous display |
| ⌃⌥T | Tile All Windows |
| ⌃⌥Z | Undo the last move |
| ⌃⌥/ | What Just Happened? (see [8a](#8a-what-just-happened)) |
| ⌃⌥⌘, | Open Settings |

**Adding a hotkey:** in **Settings › Shortcuts**, choose **Add Hotkey**, pick a command (Move Window, Run Cycle, Change Columns, Move to Display, Tile All Windows, Tile Evenly, Remember Split, Forget This Split, What Just Happened?, Undo Last Move or Open Settings), then record the keys.

**Recording keys:** click the shortcut (or select it and press Space), then type the new one. Esc cancels; Delete clears.

**Conflict warnings:** if a hotkey matches a macOS shortcut, Tessera shows a warning. The hotkey still works.

**Turning them all off:** **Use global hotkeys** switches every hotkey off at once. Each one keeps its own setting for when you turn them back on. The ring still works.

---

## 5. Cycles

A cycle is a list of positions that one hotkey steps through. Press it again within **2 seconds** on the same window to move to the next step. After the last step, it wraps back to the first. A step that wouldn't move the window is skipped.

**Example:** with the default "left" cycle, press ⌃⌥← three times:
1. Left half
2. First column
3. First two columns

Edit cycles in **Settings › Cycles**. Each step is either an **Action** (such as Left half) or a **Columns** range with a band (full, top or bottom). A cycle can also be pinned to a display. Reorder steps with the arrows, or select a step's number and press ⌘↑ / ⌘↓.

> Renaming a cycle doesn't update the hotkeys that run it. Re-pick the cycle in **Settings › Shortcuts**.

---

## 6. Tiling every window

Three commands arrange **every visible window on a display** at once. They are in the menu bar under **Snap Front Window**:

| Command | What it does |
|---|---|
| **Tile All Windows** (⌃⌥T) | Places the windows side by side. Uses your [learned split](#7-learned-splits) for those apps when there is one; otherwise gives each window an equal share. |
| **Tile Evenly** | Always equal shares. Your learned split is kept for the next Tile All Windows, and changes you make afterwards are not learned. |
| **Remember Split** | Saves the current arrangement right away, without tiling. |

How a tile works:
- **Which display:** the front window's display. If no window is in front, the display under the cursor.
- **Which windows:** every visible window on that display, except apps on your [Excluded Apps](#excluded-apps) list.
- **Order:** windows keep their current left-to-right order (top-to-bottom on a portrait display).
- **Undo:** one ⌃⌥Z puts every tiled window back.

**Example:** Dia, Claude and Codex are open on the ultrawide.
- First **Tile All Windows** → three equal thirds. The message reads "Tiled 3 windows".
- Drag Dia's edge so it takes half the screen → Claude and Codex shrink to fill the rest. A second later, Tessera remembers this split.
- Next **Tile All Windows** with those three apps → Dia gets half again. The message reads "Tiled 3 windows · your split".
- Open ChatGPT as well → four apps is a different set, so the next tile gives equal quarters until you adjust it.
- **Tile Evenly** → equal thirds again, and the half-screen split is still saved.

---

## 7. Learned splits

Tessera learns how you like windows arranged, separately for each set of apps on each display.

### Neighbours follow your edits

When two or more windows sit side by side on a display, Tessera watches them. Drag one window's edge and its neighbours move to fill the space, keeping the configured gap. Nothing is left uncovered and nothing overlaps. This works from launch; you don't need to tile first. It needs both **Learn from my adjustments** and **Resize neighbours to fill the display** on (both are on by default).

### Closing a window leaves no gap

Close a window (or quit its app) while it sits side by side with others and the rest cover its space straight away:
- **Your split first.** If you've taught Tessera a split for the apps that are left on that display, they go back to it.
- **Otherwise the window you used last grows.** Of the windows beside the empty space, the one you used most recently stretches across it. A column of windows beside a closed column widens together.

Press **⌃⌥Z** to put the windows back. It needs **Learn from my adjustments** and **Fill the space when a window closes** on (both are on by default). Minimising or hiding an app doesn't count as closing.

### How a split is learned

About **1 second** after you stop adjusting, Tessera saves the arrangement as a **split**. A split is keyed by:
- **the display**, and
- **the set of apps** on it. App order doesn't matter. Two Chrome windows count as two.

The next **Tile All Windows** with the same apps on the same display reuses it. Tessera keeps up to 50 splits; the oldest is dropped first.

### Settings › Splits

| Setting | Default | Meaning |
|---|---|---|
| Learn from my adjustments | On | Off: Tessera stops watching windows, so it learns nothing new and neighbours no longer follow your edits. Splits you already saved (or save with Remember Split) are still used by Tile. To get equal shares, forget them or use Tile Evenly. |
| Resize neighbours to fill the display | On | Neighbours follow a resized window's edges. Needs **Learn from my adjustments** on. |
| Fill the space when a window closes | On | The apps left go back to their split, or the window beside the space you used last grows into it. Needs **Learn from my adjustments** on. |
| Restore last order | Off | Off: windows keep their current order and take their app's learned **size**. On: each app goes back to its exact learned **position**. |
| Empty space when order changes | Stays in place | When windows are in a new order, a learned gap either stays where it was or follows the window it sat beside. |

The list below the settings shows every learned split. **Forget** removes one; **Forget All…** removes them all. A forgotten app set tiles in equal shares again.

---

## 8. Undo

**⌃⌥Z** (or **Undo Last Move** in the menu bar) puts back the most recent move. Each press goes one step further back, up to 500 steps.

One step can cover several windows:
- a whole tile
- the neighbours that followed a resize
- the windows that filled a closed window's space

---

## 8a. What Just Happened?

Tessera can explain what it just did. A card appears beside the windows involved, the rest of the display dims, and those windows are outlined. The card says what happened in plain words and offers a fix where there is one.

**On its own:** the first time something new happens (your first tile, your first learned split, neighbours following a resize, windows filling a closed window's space), and when something surprising happens (some windows wouldn't move, an arrangement couldn't be saved as a split). Surprises show the card without the dim. Tips appear only for things you did with the ring, a hotkey, the menu bar or a drag; never for the command line, URLs, AppleScript or Shortcuts. They never take the keyboard: keep typing and the card goes away. They also close when you click into another app, press Esc, or leave the first card untouched for 12 seconds. A "Try it" step is the exception: it waits for your drag, so typing or clicking another window doesn't close it; Esc or **Skip** does.

**On request:** press **⌃⌥/** (by default), or choose **What Just Happened?** from the menu bar, to explain the latest event, whatever started it. The card then takes the keyboard: Tab moves between its buttons, Return presses the highlighted one, Esc closes it. **‹ ›** (or ← →) step through the last 10 events.

Example, after your first **⌃⌥T** with Dia, Claude and Codex:
1. **Tiled in equal shares.** No split for these apps yet, so each got a third. Choose **Show Me More**.
2. **Try it: drag this edge.** The seam between Dia and Claude pulses. Drag it; Claude and Codex move with it. **Skip** ends the tour.
3. **Claude and Codex followed.** Tessera saved this as your split. **Undo** puts the split back as it was and tiles the windows again.

The buttons only act on the windows the card is about. If they've changed since (an app closed, another opened), the card reads "These windows have changed since then." and nothing moves. **Forget This Split** forgets the split the card describes, not whatever is on screen now, and its card offers **Undo**. `tessera explain` opens the card from the command line.

**Settings › General › Help:**

| Setting | Default | Meaning |
|---|---|---|
| Show tips on their own | On | Off: cards only appear when you ask. The card's **Don't show tips** turns this off too. |
| Dim the screen behind tips | On | Off: every card, including one you ask for, shows without the dim and outline. A "Try it" step still shows its pulsing edge. |

**Show Tips Again** lets every first-time tip show once more. What Just Happened? (⌃⌥/ by default) and the menu item work whichever way these are set. Rebind its hotkey in **Settings › Shortcuts**; hide the menu item in **Settings › General › Menu bar**.

---

## 9. The menu bar menu

| Item | What it does |
|---|---|
| Hold ⌃⌥⌘ to snap | A reminder of your trigger. Reads "Accessibility not granted" until you allow it. |
| What Just Happened? | Same as its hotkey (⌃⌥/ by default): explains the latest thing Tessera did. |
| Snap Front Window › | Tile All Windows, Remember Split, Tile Evenly, then every layout (Maximise, Centre, halves, quarters). |
| Columns › | One More Column, One Fewer Column, 2–8 Columns, for the front window's display. |
| Settings… | Opens Settings (⌃⌥⌘, by default; ⌘, while the menu is open if you clear that hotkey). Reads **Finish Setup…** until Accessibility is allowed. |
| Shortcuts… | Opens Settings › Shortcuts. |
| Undo Last Move | Same as ⌃⌥Z. |
| Check for Updates… | Reads **Update Available…** when a new version is waiting. |
| Quit Tessera (⌘Q) | Quits. |

Each item shows its hotkey at the right edge, the way any Mac menu does, and follows any change you make in **Settings › Shortcuts**. Items with no hotkey show none. Turn this off with **Show each item's shortcut**.

The icon turns into a warning triangle when Accessibility isn't granted. Choose which items show, and the icon's picture, in **Settings › General › Menu bar**.

> If you hide the menu bar icon, open Tessera from Finder or Spotlight to reach Settings.

---

## 10. Settings, pane by pane

Open Settings with **⌃⌥⌘,**, from the menu bar, or by opening Tessera again. **⌘1–⌘9** switch panes; **⌘0** opens About. Every control can be reached with Tab.

### General
- **Trigger:** click the chord, hold the modifier keys you want, and release. Delete resets it to the default. A single-key chord opens the ring every time you press that key.
- **Appearance:** Light, Dark or Match System, for Tessera's own windows.
- **Launch at login.** You may need to approve it in System Settings › General › Login Items.
- **Menu bar:** show or hide the icon, pick its picture (Grid, Columns, Halves, Quarters, Window, Ring), and choose which menu items appear and whether each shows its shortcut.
- **Messages:** short on-screen confirmations such as "5 columns". Choose the position (Top, Centre, Bottom) and how long they stay (1.2 s by default).
- **Help:** tips that appear on their own, the dim behind them, and **Show Tips Again**. See [What Just Happened?](#8a-what-just-happened).
- **Updates:** check automatically (daily, weekly, fortnightly or monthly), download and install automatically, include beta versions, or **Check Now**.
- **Import and export:** saves all settings to one JSON file, or loads them. Import replaces every setting; an invalid file is rejected and nothing changes.
- **Command line:** **Install Command-Line Tool** links `tessera` into `~/.local/bin`. See [Automation](#11-automation).

### Excluded Apps
While an excluded app is in front, the trigger and hotkeys do nothing. Its windows are also left out of Tile. Use **Choose App…** to add one.

### Shortcuts
Global hotkeys (see [Hotkeys](#4-hotkeys)) and the **Ring keyboard** options:
- navigate the open ring with the keyboard
- announce the selection with VoiceOver

### Cycles
See [Cycles](#5-cycles).

### Splits
See [Learned splits](#7-learned-splits).

### Displays
- **Each connected display:** column (or row) count, gap and padding, with a live grid preview. **Use Automatic** returns to the default.
- **New displays:** the gap and padding for any display you haven't changed.
- **Column sizing:** minimum, ideal and maximum column width, minimum row height, and the column limit. These decide how many columns every display can hold.

### Ring
- **Gestures:** turn Directions (flick), Pointing, Click to span, Scroll to change columns, and Tap to tile on or off. With both Directions and Pointing off, use the arrow keys and Return while holding the trigger, or the hotkeys.
- **Directions:** click a wedge, or use ← →, then choose its layout.
- **Appearance:** show or hide the ring (the gestures keep working), action names and input hints, layout icons (layout pictures or arrows), the dashed circle where pointing begins, the frosted background, grid lines, column numbers, and the "click to add columns" hint.
- **Colours:** ring tint, lines and icons, the selected layout, and the grid.
- **Size and zones:** radius, thickness, point threshold, and the top and bottom bands. If you slip into pointing by accident, raise the point threshold.

### Overlay
- **Theme:** Default, Minimal or Glass, or one you save yourself. Changing a colour on a built-in theme saves your look as a new theme; the built-in one stays as shipped.
- **Preview fill:** Tinted box (instant), Window snapshot (needs Screen Recording), or App icon. Also fill opacity, border width and corner radius.
- **Label:** show the size, the slot, or both, in the centre or at the bottom.
- **Around the preview:** dim the windows it covers (and how strongly), and outline where the window is now.
- **Show on Screen:** shows the real ring and preview for three seconds, so you can judge a theme without holding the trigger. **Preview Shortcut** shows a hotkey confirmation. Neither moves a window.

### Motion
- **Snap speed:** Instant, Snappy (0.12 s), Smooth (0.2 s), Fluid (0.3 s) or Relaxed (0.45 s), or drag to any duration. Applies to the ring and hotkeys alike.
- **Preview morph:** animate the preview between selections, with an adjustable spring.

> With **Reduce Motion** on in System Settings › Accessibility › Display, windows and the preview jump instead of animating.

---

## 11. Automation

Every surface runs the same commands as the ring and hotkeys.

### Command line

Install it from **Settings › General › Install Command-Line Tool**. If your shell can't find `tessera`, add `~/.local/bin` to your PATH.

```bash
tessera apply --cols 2-4 --band top      # columns 2 to 4, top half
tessera apply --cols -1                  # the last column
tessera action leftHalf
tessera cycle left
tessera columns --set 6 --display 2
tessera columns --delta -1
tessera move next
tessera tile                             # learned split, else equal shares
tessera tile evenly
tessera remember                         # save the current arrangement
tessera explain                          # open What Just Happened? for the latest event
tessera forget [--display D]             # forget the learned split for the apps on the display now
tessera undo
tessera displays --json
tessera window --json                    # the front window's app and frame
tessera settings open
tessera settings export ~/tessera.json
tessera settings import ~/tessera.json
```

- `--display` accepts `current`, `cursor`, a number (left to right, from 1) or `id:KEY`.
- Negative columns count from the right: `-1` is the last. Use `..` for ranges with negatives, as in `-2..-1`.

### URL scheme

```bash
open "tessera://apply?cols=2-4&band=top"
open "tessera://tile"
```

For safety, URLs can't read or write files or query state. `displays`, `window`, `settings export` and `settings import` aren't available this way, and neither is `forget`. `explain` is.

### AppleScript

```applescript
tell application "Tessera" to apply columns "2-4" band top
tell application "Tessera" to tile evenly
```

Commands: apply columns, perform action, run cycle, set columns, change columns, move to display, tile evenly, remember split, undo move, list displays, describe window, open settings. Open Tessera's dictionary in Script Editor for the full syntax.

### Shortcuts and Spotlight

Search for "Tessera" in the Shortcuts app. Actions: Apply Columns, Perform Action, Run Cycle, Set Columns, Change Columns, Move to Display, Tile All Windows, Tile Evenly, Undo Move, List Displays, Describe Window, Open Settings.

---

## 12. Troubleshooting

| Symptom | Fix |
|---|---|
| Holding the trigger does nothing | Allow Accessibility (the menu bar icon shows a warning triangle until you do). Also check that the front app isn't in Excluded Apps, and that Ring › Gestures or the Ring keyboard is on. |
| "This app is excluded in Tessera settings" | Remove the app in Settings › Excluded Apps. |
| Accessibility is on but still not granted | In setup, choose **Fix permission**, then grant again. |
| The preview is a plain box, not a picture | Choose Window snapshot in Settings › Overlay and allow Screen Recording. macOS asks you to quit and reopen Tessera. |
| You keep slipping into pointing | Raise the point threshold in Settings › Ring › Size and zones. |
| Tile uses an old layout you no longer want | Forget it in Settings › Splits, or use Tile Evenly. |
| A hotkey shows a warning | It clashes with a macOS shortcut. It still works, but pick another key if the system one matters to you. |
| Windows jump instead of gliding | Reduce Motion is on, or Snap speed is set to Instant. |
