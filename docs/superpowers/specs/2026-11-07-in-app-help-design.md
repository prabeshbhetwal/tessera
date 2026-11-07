# In-app help: coach overlay, live guide and tips

Status: design, awaiting approval. Date: 2026-11-07.

## Why

Tessera does things a person can't see coming. The clearest example: the author asked whether Tile All Windows uses equal shares or the split it learned. The answer depends on hidden state: the apps on the display, whether a split was learned for that set, and when. A day earlier the same author couldn't tell why neighbours didn't resize until Tile had been run once.

If the person who built the app gets confused, other users will too. `docs/USER-GUIDE.md` now explains every feature, but nobody opens a manual at the moment of confusion. Help has to appear **where and when the confusion happens**, use the app's **real state** (these windows, this split, this date), and let the person **try the next step on their own windows**.

Success looks like this:
- A first-time user runs Tile, and before reading anything they know whether they got equal shares or a learned split, and how to get the other.
- When something doesn't happen (the trigger is ignored, neighbours don't follow), Tessera says why, on screen, and offers the fix.
- An experienced user never sees help they didn't ask for, beyond the first encounter with each feature.

## Decisions made by Sir

1. **Build all four ideas:** the explainer, the live guide, practice and habit tips.
2. **The explainer covers three kinds of event:** commands, silent changes (neighbours reflowed, a split learned) and non-events (input ignored, neighbours didn't follow).
3. **The explainer is a full-screen coach overlay, not a popover or a menu.** The display dims, the windows involved are spotlighted, and a card says "this is what happened; if you do this, this will happen". The person tries it on their real windows.
4. **When it appears on its own:** the first time the person meets each feature, plus results that may surprise them. After that, only on request.
5. **The live guide lives in both places:** its own window (menu bar "Tessera Guide…" and ⌘? in any Tessera window), and a "?" button on each Settings pane that opens the matching section.
6. **Teaching never destroys what the person taught.** When a coach step changes or forgets a learned split, **Undo** (or the card's undo) restores the split as it was before, not just the window frames.
7. **Everyone sees the first-time coaching once,** including existing installs after the upgrade. Nothing is pre-marked as seen. One "Don't show tips" click turns it off.
8. **Onboarding gains more steps,** rather than handing everything to the coach. It teaches the core in order on first launch. The coach covers what onboarding skipped, and anything later.

## Goals

- **Explain the last thing that happened,** with live facts and one-click fixes.
- **Teach by doing:** each explanation can continue into "try this", wait for the person to do it on their real windows, then confirm what that did.
- **Ship one searchable guide** that shows the person's own values and can start any coach tour on screen.
- **Offer rare, habit-based tips** for faster ways to do what the person already does.
- **Use one source of content:** `docs/USER-GUIDE.md` and the in-app text must not drift apart.

## Non-goals

- Video or animated tutorials outside the overlay (the onboarding animation stays as it is).
- Help for macOS itself.
- Analytics, telemetry or any data leaving the Mac. "Seen" and habit counts stay in local settings.
- Replacing onboarding. It stays as the first-launch path and gains steps (part 6).

## Anti-goals (these would make it a failure even if it works)

- **Help that blocks work.** The dimmed layer must never swallow a click, drag, scroll or keypress meant for the person's apps.
- **Nagging.** Repeated auto-shown coaching for something already seen, or more than one habit tip a day.
- **Marketing tone:** exclamation marks, badges, streaks, "Did you know?!". PRODUCT.md says: precise, quiet, native.
- **Moving windows on its own.** Tessera moves windows only when the person clicks a fix button or does the step themselves. The one exception is practice windows Tessera owns.
- **Slowing the Ring.** Nothing here may add work to the Ring's per-cursor update path.

## The parts

### 1. Event journal (foundation)

Every explanation starts from a recorded event. Tessera keeps the **last 10 events** in memory (not persisted). Each event holds:

- **Kind:** for example tiledWithSplit, tiledEvenly, tiledEqualNoSplit, neighboursFollowed, splitLearned, splitForgotten, snapped, cycled, columnsChanged, movedToDisplay, undone, triggerIgnored(reason), reflowSkipped(reason), tilePartial.
- **Facts:** the display, the apps and windows involved, frames before and after, and the split's learned date where relevant.
- **The split as it was before,** for any event that saves, replaces or forgets a split (or "none"). Undo and the card's fix buttons use it to put the person's split back (decision 6).
- **Source:** where the command came from (Ring, hotkey, menu bar, coach button, CLI, URL, AppleScript or Shortcuts). `CommandBridge.execute` takes the source alongside the command.
- **Suggested fixes,** each one an existing `Command`: Tile Evenly, Forget Split (a new command, see below), Undo, Open Settings pane, Remove from Excluded Apps.
- **Whether it counts as a surprise** (see part 2).

Sources:
- `CommandExecutor`: command results.
- `SplitWatcher` / `SplitWatchers`: reflowed, learned, skipped.
- `Coordinator` / `InputService`: trigger ignored, because the app is excluded or gestures are off. A missing permission can't be detected this way, since the event tap needs Accessibility to exist. The menu bar warning and onboarding still cover that case.

The pure parts belong in `TesseraCore`: the event type, the buffer, the surprise rule, the first-time rule, and the text for each event built from its facts. They need unit tests.

### 2. Coach overlay

What the person sees (mockup: `.superpowers/brainstorm/…/coach-overlay.html`):

1. **Dim and spotlight.** The display where the event happened dims (about 45%). The windows involved are cut out and outlined in the theme accent colour. Other displays are untouched.
2. **A card beside the spotlight,** with an arrow pointing at it. It has a title, one or two sentences of live facts, buttons, and "n of m" when the event has more steps.
3. **Steps follow "what happened → if you do this → what that did".** For a tile with a split:
   1. **What happened:** "Tiled with your split. You taught Tessera this split for Dia, Claude and Codex on 7 Nov: Dia half, the others a quarter each. Without it, each would get a third." Buttons: Show Me More, Tile Evenly Instead, Got It.
   2. **If you do this:** the seam between two windows pulses. "Try it: drag this edge. Claude and Codex will move with it." The step waits until the person drags the real edge. A Skip button is available.
   3. **What that did:** "Claude and Codex followed. Tessera saved this as your new split. Press ⌃⌥T any time to get it back." Buttons: Done, Undo. **Undo** puts the windows back *and* restores the split from 7 Nov.
4. **The dim layer is click-through.** It's a separate non-activating panel with `ignoresMouseEvents = true`, so step 2's drag reaches the real window.
5. **The card takes clicks.** It's a separate panel that accepts first mouse. This is a deliberate, scoped exception to AGENTS.md's "overlay panels ignore mouse input" rule, and AGENTS.md must be updated to say so.
6. **Focus and keys** *(my call)*:
   - **Shown on its own:** the card never becomes key and never takes focus. Its buttons work by mouse only, and Tessera doesn't intercept any key, Esc included. It closes on a button, its timeout, or a click into another app. Nothing the person types is swallowed.
   - **Opened on request** (⌃⌥/, the menu, the guide): the person asked for it, so the card may become key. Tab, Return and Esc then work in the card as in any window, and focus goes back to the previous app when it closes.

When it shows on its own:
- **First time:** the first occurrence of each coach moment. Seen moments are stored in settings.
- **Surprises** *(builder's call, may be tuned):*
  - `tilePartial`: some windows didn't move
  - `triggerIgnored` and `reflowSkipped`: the first occurrence of each reason per day
  - a tile used a split while the person's last tile of the same apps had equal shares, or the reverse
- **Never** while the Ring is open, during a drag, or within 2 s of the person typing *(builder's call)*.
- **Only for interactive sources** *(my call)*: the Ring, hotkeys and the menu bar. Commands from the CLI, URL scheme, AppleScript or Shortcuts are recorded in the journal (so ⌃⌥/ can explain them) but never show the coach on their own, so a script can't dim the screen. A command fired by a coach button never starts a new coach about itself.

How it gets out of the way *(builder's call)*:
- Step 1 fades after 12 s untouched, or as soon as the person types or clicks into another app.
- A waiting "try this" step has no timeout, but closes on Esc, Skip, or a click into another app.
- **Non-events and surprises use the light form:** the card only, with no dimming and a "Show Me" button that expands into the full coach. Dimming the screen because the trigger was ignored would feel like punishment.

On request:
- **⌃⌥/** (a new default hotkey, rebindable) and the menu bar item **"What Just Happened?"** open the full coach for the latest event.
- **‹ ›** on the card step back through the journal.

Comfort and access:
- **Reduce Motion:** no pulse, fades only.
- **Colours:** follow the theme accent and label colours.
- **VoiceOver:** reads the card text and buttons, and the spotlight has a description ("Dia, Claude and Codex, side by side").
- **Copy:** Australian English, and no exclamation marks.

A "Don't show tips" switch, in the card footer and in Settings › General › Help, turns off everything that appears on its own. ⌃⌥/, the menu item and the guide keep working.

### 3. Live guide

**Its own window: "Tessera Guide".**
- Opens from the menu bar ("Tessera Guide…"), with ⌘? in any Tessera window, and with the new `guide` command.
- **Layout:** a sidebar of the 12 sections of `USER-GUIDE.md` and a search field at the top.
- **Live values:** each section shows the person's real state where it matters:
  - Columns: each display, its count and its allowed range.
  - Hotkeys: the current bindings, with conflict warnings.
  - Splits: the learned splits for the displays connected now.
  - Excluded Apps: the current list.
- **Buttons:** **Show Me on My Screen** runs that section's coach tour on the person's real windows. **Open Setting** jumps to the matching Settings pane.
- **Search:** matches section text *and* commands. Typing "tile evenly" lists the section and a **Run** row, and Return runs the command.

**"?" buttons:** each Settings pane gets a "?" button in its header that opens the guide at the matching section.

**One source:** the guide's text comes from the same source as `docs/USER-GUIDE.md`. The builder picks how:
- bundle and parse the Markdown by heading, or
- define sections as structured data and generate the Markdown from them.

A test must fail if the two drift.

### 4. Practice windows

When a coach tour or **Show Me** needs more windows than the display has (Tile and splits need two or more), the card offers **Use Practice Windows**. Tessera opens two or three plain windows of its own, labelled A, B and C, runs the tour on them, and closes them when the tour ends or is cancelled.

The person's real windows aren't moved. Practice windows are left out of learned splits, so a tour never saves a split.

How this works *(my call)*: the tour runs real commands **scoped to the practice windows only**. A practice Tile places just A, B and C, using the same geometry as Tile, inside the free part of the display or over the whole display above the real windows. The same goes for reflow. This means lifting `WindowService`'s own-process exclusion **for practice windows only**, while Tessera's Settings and Guide windows stay excluded. The ordinary Tile, hotkeys and `SplitWatchers` never see practice windows.

### 5. Habit tips (quiet coach)

The light card form, with no dimming, suggests a faster way to do something the person keeps doing. Starting set *(builder's call)*:
- Snapping the same window with a flick and then a column hotkey within 2 s, three times → "⌃⌥← cycles through both."
- Changing the column count by scrolling on one display often → "Settings › Displays keeps a count per display."
- Dragging window edges by hand into a side-by-side arrangement with no Tile → "⌃⌥T lines them up, and Tessera remembers your adjustments."

Limits:
- At most **one tip a day**, each tip shown **once**.
- Turned off by the same "Don't show tips" switch.
- Habit counts stay in local settings and are never sent anywhere.

### 6. Onboarding (extended)

`Tessera/UI/OnboardingView.swift` keeps its four steps and gains four. The step list is *my call*:

| # | Step | Status | Interactive part |
|---|---|---|---|
| 1 | Snap windows with the ring | existing | demo animation |
| 2 | Allow Accessibility | existing | Grant… |
| 3 | Live window thumbnails | existing, optional | Allow… |
| 4 | Try the ring | existing | waits for a real snap |
| 5 | Your displays | new | lists each connected display live with its column count and allowed range (for example "CHG90: 5 columns, 3 to 6 fit"). "Scroll while holding the trigger" updates the shown count when the person does it. |
| 6 | Hotkeys | new | the key bindings as currently set (⌃⌥← →, ⌃⌥↑ ↓, ⌃⌥T, ⌃⌥Z, ⌃⌥/). "Press ⌃⌥← twice" waits and confirms each cycle step. |
| 7 | Tile and splits | new | "Press ⌃⌥T", then "drag an edge", then the result, in the same words as the coach. It offers practice windows (part 4) when fewer than two windows are on the display. |
| 8 | You're set | new | where the Guide is (⌘?), what ⌃⌥/ does, and the "Don't show tips" switch. |

Rules:
- **Steps 5–8 each have Skip.** Step 4 keeps its current behaviour.
- **Finishing a step marks the matching coach moments as seen:**
  - step 4: the ring moments
  - step 6: the cycle moment
  - step 7: the tile, neighbours-followed and split-learned moments

  The coach therefore never repeats what onboarding just taught. Skipped steps leave their moments unseen, so the coach catches them later.
- **The hotkeys shown are the person's real bindings.** If a hotkey is turned off or rebound, the step uses the current key, or leaves the row out.
- **Copy is shared:** the onboarding text for steps 5–7 comes from the same source as the guide and the coach.
- **Existing installs don't see onboarding again.** The new steps reach them through the coach's first-time moments (decision 7). **Settings › General** gets a "Show Setup Again" button.

## New commands and settings

**Commands** (every surface goes through `CommandBridge`):
- `explain`: open the coach for the latest event.
- `guide [section]`: open the guide.
- `forgetSplit(display:)`: forget the split for the apps on that display now. From the CLI and menus it acts on the current apps. The coach's **Forget This Split** button instead forgets the event's own recorded split key, so stepping back with ‹ › never forgets the wrong split. The forget can be undone (decision 6).

The CLI, URL scheme, AppleScript and Shortcuts get these where they make sense. `explain` and `guide` are safe over URL.

**Settings** (optional fields so older settings files still decode, the same pattern as `RingSettings.boundary`):
- `help.autoShow` (on): the "Don't show tips" switch.
- `help.habitTips` (on).
- `help.seenMoments`: a set of moment IDs.
- `help.lastTipDate`.
- `help.habitCounts`.
- **"Show Tips Again"** in Settings › General › Help clears the seen moments and tip history.

**Hotkey:** a new default binding `explain` on ⌃⌥/. The builder checks it against `SystemHotkeys` for conflicts. Settings migration doesn't add new default hotkeys today, so existing installs get the binding added when ⌃⌥/ isn't already taken by one of their hotkeys.

**Seen moments** start empty for every install, upgrades included (decision 7).

**Split undo:** `WindowUndoHistory` steps today hold only frames. A step made by a split change also carries the split as it was before, and undoing that step restores it in `learnedSplits`.

## Constraints

- macOS 15, AppKit services and Core Animation overlays, as in the rest of `Tessera/`. Pure logic goes in `TesseraCore` with tests.
- New Swift files stay under 300 lines. `Coordinator.swift` (501 lines) and `CommandExecutor.swift` (299) must not grow: the coach and journal get their own components.
- **Ring and preview panels stay non-activating and mouse-transparent.** Only the coach card panel takes clicks, and AGENTS.md records that exception.
- **Clean room:** nothing from `loop/`.
- **Visible copy** follows `docs/DESIGN.md` and PRODUCT.md: Australian English, native controls, keyboard reachable (the card's buttons work with Tab and Return when the card is opened on request).

## Order of work

1. **Event journal and coach overlay**, for the Tile and split family: tile with split, tile with equal shares, Tile Evenly, neighbours followed, split learned, reflow skipped. Plus ⌃⌥/ and "What Just Happened?". This answers both of Sir's real confusions.
2. **Onboarding steps 5–8,** reusing the coach's text and its seen-moment marking.
3. **Live guide window**, "?" buttons, and "Show Me on My Screen" for the moments built in step 1.
4. **Remaining coach moments:**
   - the ring (flick, point, click to span, scroll)
   - cycles
   - columns
   - move to display
   - undo
   - trigger ignored

   Also practice windows.
5. **Habit tips.**

Each step ships on its own and is usable without the next.

## Calls made in the design (not decided by Sir; check these)

- **Focus:** a card shown on its own never takes focus or intercepts keys. A card opened on request may become key.
- **Interactive sources only:** only the Ring, hotkeys and the menu bar auto-show the coach. Scripted commands are journalled silently, and coach buttons never trigger a coach.
- **Practice windows:** real commands scoped to Tessera's practice windows, not a simulation.
- **Forget This Split** acts on the event's recorded split, not on whatever apps are showing now.
- **⌃⌥/** is added to existing installs only where it's free.
- **Permission missing** is dropped as an ignored-trigger reason, because it can't be detected.
- **Show Me tours** never move the person's windows on their own. A tour's first step explains, and any move happens because the person does the "try this" step or clicks a fix.
- **The light card** (no dimming) is used for non-events and surprises.
- **Timing:** the timeouts and the 1-tip-a-day limit.
- **Onboarding:** the four new steps and their order (Your displays, Hotkeys, Tile and splits, You're set). Finished steps mark the matching coach moments as seen. Existing installs don't see onboarding again; Settings gets a "Show Setup Again" button.

## Left to the builder

- Panel and layer structure for the dim, spotlight and card (reuse `OverlayController` patterns where they fit).
- The exact surprise rules, timeouts, dim strength and card placement (avoiding screen edges and the menu bar).
- How the guide content is shared with `USER-GUIDE.md`, with the drift test either way.
- How to detect that a drag didn't reflow when the windows aren't watched. **Known risk:** `SplitWatcher` only observes side-by-side groups, so a drag on overlapping windows is invisible today. A cheap observer on the front window may be enough.
- Practice window styling, and leaving them out of splits.
- Copy for each moment, written from the guide's text.
