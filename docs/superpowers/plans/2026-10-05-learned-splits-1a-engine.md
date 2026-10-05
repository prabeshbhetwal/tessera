# Learned Splits 1a (Engine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tile learns each display's hand-made window arrangement and reuses it; "Remember Split" saves one on demand; a minimal Splits pane lists and forgets them.

**Architecture:** Pure learning/applying/memory logic in `TesseraCore/Splits` (unit-tested). The app side adds an Accessibility-notification watcher, routes Tile and the new `rememberSplit` command through it, and shows a plain Splits pane. Learned splits persist in the existing settings file.

**Tech Stack:** Swift 6, Swift Testing, AppKit, ApplicationServices (`AXObserver`), SwiftUI, XcodeGen (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-10-05-learned-splits-design.md`

## Global Constraints

- Every source file ≤ 300 lines. Don't grow `Coordinator.swift` (469) beyond the one wiring line in Task 6.
- Australian English in visible copy. Command identifiers stay as they are.
- New `TesseraSettings` keys are plain properties with defaults: `SettingsMigration` fills missing keys, so there's no Optional and no schema bump (`currentSchemaVersion` stays 2).
- Tessera never moves a window unless a command runs. The watcher only reads frames.
- Overlap tolerance is 24 pt. Gaps up to the display gap + 8 pt snap. The learned-split cap is 50. The watcher debounce is 1 s.
- Messages go through `Coordinator.showHUD`, so the existing Show messages, position and duration settings apply.
- Core tests: `swift test --package-path Packages/TesseraCore --scratch-path ~/Library/Caches/tessera-build/core-learned-splits` (sandbox off).
- App build: `TESSERA_DERIVED_DATA=~/Library/Caches/tessera-build/dd-learned-splits scripts/build-app.sh` (sandbox off).

## Review Focus

1. **Window without a bundle ID** (some helper or Electron windows): the key must still be stable, so Tile and learning don't flip-flop. Test in Task 1.
2. **Hand-edited or stale learned split** (slot apps don't match its key): Tile must fall back to equal shares, not crash or quarantine the settings file. Validation rejects only non-finite or out-of-range numbers. Test in Task 3.
3. **Window partly outside the usable frame** (under the Dock or off-screen): the learner clips it instead of storing a rectangle over 1. Test in Task 2.
4. **Single-window group:** a lone window at 70% with a strip of desktop learns and re-applies. Test in Tasks 2 and 3.
5. **Repeated learning of the same group:** upsert replaces and never duplicates, and the cap drops the oldest. Test in Task 1.

---

### Task 1: Split model and memory

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Splits/LearnedSplit.swift`
- Create: `Packages/TesseraCore/Sources/TesseraCore/Splits/SplitMemory.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/SplitMemoryTests.swift`

**Interfaces:**
- Produces (all `public`, `Codable, Equatable, Sendable`):
  - `struct UnitRect { var x, y, width, height: Double }`: fractions of a usable frame, AppKit orientation (y from the bottom). Provides `func absolute(in usable: CGRect) -> CGRect` and `init(_ rect: CGRect, in usable: CGRect)`.
  - `struct Slot { var bundleID: String; var rect: UnitRect }`
  - `struct SplitKey: Hashable { let display: String; let apps: [String] }`, plus `init(display: String, bundleIDs: [String?])`. It stores `apps` sorted, with repeats kept, and maps nil to `"?"`.
  - `struct LearnedSplit { var key: SplitKey; var slots: [Slot]; var updated: Date }`
  - `enum SplitGapPlacement: String, CaseIterable { case staysInPlace, followsNeighbour }`
  - `enum SplitGapWhenGrowing: String, CaseIterable { case fixed, shrinks }`
  - `enum SplitMemory`:
    - `static let capacity = 50`
    - `static func lookup(_ key: SplitKey, in: [LearnedSplit]) -> LearnedSplit?`
    - `static func upsert(_ split: LearnedSplit, into: [LearnedSplit]) -> [LearnedSplit]` (newest last)
    - `static func forget(_ key: SplitKey, in: [LearnedSplit]) -> [LearnedSplit]`

- [ ] **Step 1: Write the failing tests** in `SplitMemoryTests.swift` (`@Suite struct SplitMemoryTests`):
  - `keyIgnoresAppOrder`: `SplitKey(display: "d", bundleIDs: ["b", "a", "a"]) == SplitKey(display: "d", bundleIDs: ["a", "b", "a"])`, and `.apps == ["a", "a", "b"]`.
  - `keyDistinguishesCountAndDisplay`: `["a"]` ≠ `["a", "a"]`, and display `"d1"` ≠ `"d2"`.
  - `keyMapsMissingBundleToPlaceholder` (Review Focus 1): `SplitKey(display: "d", bundleIDs: [nil, "a"]).apps == ["?", "a"]`.
  - `unitRectRoundTrips`: with `usable = CGRect(x: 100, y: 50, width: 1000, height: 500)`, `UnitRect(CGRect(x: 350, y: 50, width: 500, height: 250), in: usable)` is `(0.25, 0, 0.5, 0.5)`, and `.absolute(in: usable)` returns the original rect.
  - `upsertReplacesSameKeyAndMovesToNewest` (Review Focus 5): upserting key K twice leaves one K entry, and it's last.
  - `capDropsOldest`: upserting 51 distinct keys gives 50 entries, with the first key gone.
  - `forgetRemovesOnlyThatKey` and `lookupFindsByKey`.
- [ ] **Step 2: Run them and confirm they fail.** Run the core test command. Expected: compile errors for the missing `SplitKey` and others.
- [ ] **Step 3: Implement the types in `LearnedSplit.swift` and `SplitMemory` in `SplitMemory.swift`**, using the exact interfaces above.
- [ ] **Step 4: Run the core tests.** Expected: all pass (282 existing plus the new ones).
- [ ] **Step 5: Commit.** `git commit -m "feat(core): learned split model and memory"`

### Task 2: SplitLearner

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Splits/SplitLearner.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/SplitLearnerTests.swift`

**Interfaces:**
- Consumes: `Slot`, `UnitRect` (Task 1).
- Produces:
  - `public enum SplitRejection: Error, Equatable { case noWindows, overlap }` with `var message: String`: "No windows on this display" / "Windows overlap, so there's no split to remember".
  - `public enum SplitLearner`:
    - `static let overlapTolerance: Double = 24`
    - `static func learn(_ windows: [(bundleID: String?, frame: CGRect)], usable: CGRect, gap: Double) -> Result<[Slot], SplitRejection>`
    - `static func readingOrder(_ rects: [CGRect]) -> [Int]`: indices in reading order, top row first, left to right.

Algorithm (the tests pin it):
1. Clip each frame to `usable`.
2. Reject if any pair overlaps by more than 24 pt in both width and height.
3. Snap: an outer edge within `gap + 8` of a usable edge moves onto that edge. A gap between two adjacent windows that is within `gap + 8` becomes exactly `gap`.
4. Convert to `UnitRect` and return the slots in reading order. Two rects share a row when their vertical overlap exceeds half the smaller height.

- [ ] **Step 1: Write the failing tests.** Fixture: `usable = CGRect(x: 0, y: 0, width: 1000, height: 500)`, `gap = 8`.
  - `twoWindowRow`: frames x 0…300 and 308…1000 (full height) give rects `(0, 0, 0.3, 1)` and `(0.308, 0, 0.692, 1)`.
  - `sloppyEdgesSnap`: a window starting at x = 5 snaps to x = 0; a 12 pt gap between windows becomes 8 pt.
  - `largeGapKept` (strip): one window at 0…800 keeps width 0.8; nothing fills the right 20%. This also covers Review Focus 4.
  - `gridAccepted`: four quarter windows give 4 slots, in reading order top-left, top-right, bottom-left, bottom-right.
  - `overlapRejected`: two windows overlapping by 100 × 500 → `.failure(.overlap)`.
  - `smallOverlapTolerated`: a 20 pt overlap still succeeds.
  - `emptyRejected`: `[]` → `.failure(.noWindows)`.
  - `clipsOffscreen` (Review Focus 3): a frame at x −200…400 is stored as x = 0, width 0.4.
  - `nilBundleBecomesPlaceholder`: the slot's `bundleID == "?"`.
- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement `SplitLearner`** in `SplitLearner.swift`, with the signatures above.
- [ ] **Step 4: Run the core tests.** Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(core): learn splits from window frames"`

### Task 3: SplitApplier

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Splits/SplitApplier.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/SplitApplierTests.swift`

**Interfaces:**
- Consumes: `LearnedSplit`, `Slot`, `UnitRect`, `SplitGapPlacement`, `SplitLearner.readingOrder` (Tasks 1–2).
- Produces: `public enum SplitApplier { static func frames(for split: LearnedSplit, windows: [(bundleID: String?, frame: CGRect)], usable: CGRect, portrait: Bool, restoresOrder: Bool, gapPlacement: SplitGapPlacement) -> [CGRect]? }`. It returns one target frame per input window, in input order. It returns nil when the windows' bundle multiset doesn't equal the split's slot apps.

Algorithm:
1. **Pair** windows with slots by app. For each bundle ID (a nil bundle ID counts as `"?"`, matching `SplitKey`), take its windows in current reading order and its slots in stored order, then zip.
2. **Restore exactly** when `restoresOrder` is set, or when the slots aren't a single line: each window gets its paired slot's rectangle. A single line is a row; a column on `portrait`. A row means every pair overlaps vertically by more than half the smaller height; a column is the same along x.
3. **Otherwise, pack** along the axis.
   - Take the learned gaps from the slots sorted along the axis: g₀ is the leading gap, gᵢ the gap after slot i−1, g_N the trailing gap.
   - Go through the windows in current axis order. Each takes its paired slot's size along the axis, and keeps that slot's own offset and size across the axis.
   - **`.staysInPlace`:** gap gᵢ stays at sequence index i.
   - **`.followsNeighbour`:** each slot carries the gap that followed it, and the first learned slot also carries g₀ before itself.
4. Convert to absolute coordinates with `UnitRect.absolute(in: usable)`.

- [ ] **Step 1: Write the failing tests.** Fixtures: `usable = CGRect(x: 0, y: 0, width: 1000, height: 500)`; apps T, S, X.
  - `restoresAppSizesInCurrentOrder`:
    - Learned split, left to right: T 0.25, S 0.25, X 0.5, all full height, no gaps.
    - Current order: X, T, S.
    - Expected widths 500, 250, 250 at x = 0, 500, 750 (spec: sizes follow the app, current order).
  - `restoresOrderWhenAsked`: same input with `restoresOrder: true` gives T at 0, S at 250, X at 500.
  - `stripStaysInPlace`:
    - Learned: T 0…0.3, X 0.3…0.8, then 0.2 empty at the right.
    - Current order: X, T. Expected: X 0…500, T 500…800, right strip still empty.
  - `stripFollowsNeighbour`: learned T 0…0.3, gap 0.2, X 0.5…1.0; current order X, T → X 0…500, T 500…800, then the gap 800…1000 that followed T.
  - `duplicatesPairInReadingOrder`: learned Chrome 0.3 | Chrome 0.7, current windows unchanged → widths 300 and 700.
  - `gridAlwaysRestores`: a 2×2 learned split with windows in a new order → every window gets its app's learned rect, even with `restoresOrder: false`.
  - `scalesToNewUsableFrame`: the same split applied to a 2000 × 1000 usable frame doubles every frame.
  - `singleWindowStrip` (Review Focus 4): learned X 0…0.7 → X at 0…700.
  - `mismatchedAppsReturnNil` (Review Focus 2): a split with apps [T, S] applied to windows [T, X] → nil.
  - `portraitColumnPacksAlongY`: on a portrait display, a column split packs vertically.
- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement `SplitApplier.frames`** in `SplitApplier.swift`.
- [ ] **Step 4: Run the core tests.** Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(core): apply learned splits"`

### Task 4: Settings, migration and validation

**Files:**
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Model/Settings.swift` (the `TesseraSettings` stored properties, after `snapDuration`). If the file passes 300 lines, move `SnapSpeed` to `Model/SnapSpeed.swift`.
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Settings/SettingsValidation.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/SplitSettingsTests.swift`

**Interfaces:**
- Produces these `TesseraSettings` properties:
  - `var learnSplits = true`
  - `var splitRestoresOrder = false`
  - `var splitGapPlacement: SplitGapPlacement = .staysInPlace`
  - `var splitGapWhenGrowing: SplitGapWhenGrowing = .fixed`
  - `var learnedSplits: [LearnedSplit] = []`

- [ ] **Step 1: Write the failing tests.**
  - `defaults`: the five defaults above.
  - `oldFileGainsSplitKeys`: encode defaults to a JSON object, remove the five keys, run `SettingsMigration.migrate` and decode. Expected: the decoded value equals `TesseraSettings.defaults`, and `SettingsValidation.validate` passes.
  - `roundTripsLearnedSplit`: a settings value with one `LearnedSplit` survives encode → decode.
  - `validationRejectsBadRects`: a slot with `width = .nan`, or `x + width > 1.0001`, or `width <= 0` → throws `SettingsError.invalid`.
  - `validationRejectsOverCap`: 51 learned splits → throws.
  - `validationAllowsMismatchedApps` (Review Focus 2): a split whose slot apps differ from its key → validates (the applier ignores it at Tile time).
- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Add the properties and validation rules.** Use the existing `require` helper. Messages:
  - "A learned split has an invalid size."
  - "Too many learned splits (at most 50)."
- [ ] **Step 4: Run the core tests.** Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(core): persist learned splits in settings"`

### Task 5: SplitWatcher

**Files:**
- Create: `Tessera/Services/SplitWatcher.swift`
- Create: `Tessera/UI/SplitLabel.swift`

**Interfaces:**
- Consumes: `WindowService.frame(of:)` and `visibleWindows(on:primaryHeight:excluding:)`; `SplitLearner`, `SplitMemory`, `SplitKey` (Tasks 1–2); `SettingsModel`.
- Produces:
  - `@MainActor final class SplitWatcher`:
    - `init(windows: WindowService, model: SettingsModel)`
    - `var onLearned: ((String) -> Void)?`
    - `func watch(_ group: [WindowRef], key: SplitKey, display: DisplayContext, ignoreUntil: ContinuousClock.Instant)`
    - `func stop()`
    - `static let debounce: Duration = .seconds(1)`
    - `static let settle: Duration = .milliseconds(300)`
  - `@MainActor enum SplitLabel`:
    - `static func apps(_ key: SplitKey) -> String`: "Chrome ×2, Slack". Names come from `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` plus `FileManager.default.displayName(atPath:)` without ".app"; "?" shows as "Unknown app".
    - `static func display(_ key: SplitKey, displays: [DisplayContext]) -> String`: the matching display's `NSScreen.localizedName`, else "Disconnected display".

Behaviour:
- `watch` first calls `stop()`. If `model.settings.learnSplits` is false it returns.
- Otherwise it creates one `AXObserver` per pid. A `@convention(c)` callback hops to the main actor with `MainActor.assumeIsolated`, because the observer runs on the main run loop.
- It registers `kAXMovedNotification`, `kAXResizedNotification` and `kAXUIElementDestroyedNotification` on each window element, and adds `AXObserverGetRunLoopSource` to `CFRunLoopGetMain()` in `.defaultMode`.
- Destroyed → `stop()`. Events before `ignoreUntil` are ignored. Any other event cancels and restarts a debounce `Task` (1 s), which then calls `learnNow()`.
- `learnNow()`:
  1. Stop if `learnSplits` is now off.
  2. Re-read `visibleWindows` on `display.frame`. If its `SplitKey` ≠ the watched key (a window joined, left or moved display), stop.
  3. Run `SplitLearner.learn` with `GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)` and `display.profile.gap`.
  4. On success, `model.settings.learnedSplits = SplitMemory.upsert(...)` and `onLearned?("Learned split · \(SplitLabel.apps(key)) · \(display name)")`.
  5. On failure, keep watching silently.
- `stop()` removes the notifications and run-loop sources, cancels the debounce and clears its state.

- [ ] **Step 1: Implement both files** as specified. Keep `SplitWatcher.swift` ≤ 200 lines; this AX glue has no core test, and the manual checks in Task 8 cover it.
- [ ] **Step 2: Build the app.** Run the app build command. Expected: `build exit 0`, and no warnings in `SplitWatcher.swift` or `SplitLabel.swift` (check with `grep -E "^/.*Split(Watcher|Label)\.swift:[0-9]+:[0-9]+: (warning|error)"` on the build log: no output).
- [ ] **Step 3: Commit.** `git commit -m "feat(app): watch tiled windows for hand adjustments"`

### Task 6: Tile integration and the Remember command

**Files:**
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Model/Command.swift`: add `case rememberSplit(display: DisplaySelector)` after `tileWindows`.
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Commands/CommandParser.swift`:
  - Add `remember` to `verbs` (:35).
  - Add the usage line after :25: `tessera remember [--display D]           (save how the windows are arranged now; Tile reuses it)`
  - Add an arm in `build` after `case "tile":` that mirrors tile and returns `.rememberSplit(display: selector)`.
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/CommandParserTests.swift`: add `rememberCommand`.
- Create: `Tessera/App/CommandExecutor+Splits.swift`
- Modify: `Tessera/App/CommandExecutor.swift`:
  - Make `Failure` and `resolve` internal (drop `private`) so the extension can use them.
  - Add `let splitWatcher: SplitWatcher`, created in `init`.
  - Add the `run` arm `case let .rememberSplit(selector): return try await rememberSplit(selector)`.
  - In `tile`, replace `GridGeometry.tiles(ordered.count, display: display)` with `splitFrames(for: ordered, display: display)`, and after `mergeLastMoves` call `watchSplit(ordered, display: display)`.
  - Append `" · your split"` to the message when a split was used.
  - Delete the stray comment at :134.
  - **Tessera's own later moves must not teach a split** (spec: "watching ignores Tessera's own moves").
    - First line of `place(_:current:goal:)`: `splitWatcher.stop()`. This covers Ring snaps, hotkeys, Move to display, and Tile itself; Tile restarts the watch after its moves.
    - In the `.undo` arm, call `splitWatcher.stop()` before `undoLast()`.
- Modify: `Tessera/App/Coordinator.swift`: one line after the executor is created, `executor.splitWatcher.onLearned = { [weak self] in self?.showHUD($0) }`.
- Modify: `Tessera/UI/ShortcutsPane.swift`:
  - Add `case remember = "Remember split"` to `Kind`, and add it to `offered` after `.tile`.
  - `kind`: `case .rememberSplit: .remember`.
  - `defaultCommand`: `case .remember: .rememberSplit(display: .current)`.
  - `parameters`: a `DisplaySelectorEditor` like the tile arm.
  - `summary`: `case .rememberSplit(let display): return "Remember split" + on(display)`.
- Modify: `Tessera/App/StatusItemController.swift:42-45`: entries `[("Tile All Windows", …), ("Remember Split", .rememberSplit(display: .current))]` + actions, with `separatorAfter: 1`.
- Modify: `Tessera/Tessera.sdef`: add `<command name="remember split" code="TessRspl" description="Save how the windows on a display are arranged; Tile reuses it.">` with `<cocoa class="TesseraRememberSplitCommand"/>` and an optional `display` text parameter (`code="TDsp"`), copying the `set columns` entry.
- Modify: `Tessera/Automation/ScriptCommands.swift`: add `@objc(TesseraRememberSplitCommand) final class RememberSplitScriptCommand: TesseraScriptCommand`. It builds `["remember"]` plus `["--display", d]` when given.

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces, in `CommandExecutor+Splits.swift` (extension `CommandExecutor`):
  - `func splitFrames(for ordered: [(window: WindowRef, frame: CGRect)], display: DisplayContext) -> (frames: [CGRect], learned: Bool)`: `SplitApplier` with the settings when `SplitMemory.lookup` finds the key and the applier returns frames; otherwise `GridGeometry.tiles`.
  - `func watchSplit(_ ordered: [(window: WindowRef, frame: CGRect)], display: DisplayContext)`: `splitWatcher.watch(..., ignoreUntil: .now + SplitWatcher.settle)`.
  - `func rememberSplit(_ selector: DisplaySelector) async throws(Failure) -> CommandResult`:
    1. Resolve the display as `tile` does (`.current` with no front window → cursor).
    2. `visibleWindows`. If `SplitLearner.learn` returns `.failure(r)`, throw `Failure(message: r.message)`.
    3. Otherwise upsert, `watchSplit`, and return `CommandResult(ok: true, message: "Remembered split · \(SplitLabel.apps(key)) · \(display name)")`.
  - Any "Remember" without Accessibility throws the same message `tile` uses.

- [ ] **Step 1: Write the failing parser test.**
  - `rememberCommand`:
    - `cli("remember") == .rememberSplit(display: .current)`
    - `cli("remember --display 2") == .rememberSplit(display: .index(2))`
    - `url("tessera://remember?display=cursor") == .rememberSplit(display: .cursor)`
    - `expectInvalid("unexpected argument") { try cli("remember now") }`
- [ ] **Step 2: Run the core tests and confirm the new test fails.**
- [ ] **Step 3: Implement the core changes** (Command case, parser arm, verbs, usage).
- [ ] **Step 4: Run the core tests.** Expected: all pass.
- [ ] **Step 5: Implement the app changes** listed under Files.
- [ ] **Step 6: Build the app.** Expected: `build exit 0`; no new warnings in the files touched (same grep as Task 5, with these file names); `wc -l Tessera/App/CommandExecutor.swift` ≤ 300.
- [ ] **Step 7: Commit.** `git commit -m "feat: Tile uses learned splits; Remember Split command"`

### Task 7: Splits pane

**Files:**
- Create: `Tessera/UI/SplitsPane.swift`
- Modify: `Tessera/UI/SettingsView.swift`:
  - Add `case splits` after `cycles` in `SettingsPane`.
  - Fill the `title` ("Splits"), `symbol` ("rectangle.split.3x1"), `tint` (`.teal`) and `blurb` arms. The blurb is "Window arrangements Tessera learned from your adjustments."
  - In `SettingsGroup.panes`, change `control` to `[shortcuts, cycles, splits]`.
  - Add `paneView` `case .splits: SplitsPane(model: model, displays: displays)`.
  - Replace :141's `Character("\(pane.rawValue + 1)")` with a new `SettingsPane.shortcutKey: Character`: `"0"` for `.about`, otherwise `"\(rawValue + 1)"`. This fixes the `Character("10")` trap.

**Interfaces:**
- Consumes: settings properties (Task 4), `SplitMemory.forget` (Task 1), `SplitLabel` (Task 5).
- Produces: `struct SplitsPane: View { @Bindable var model: SettingsModel; let displays: DisplayService }`

Content, as a grouped `Form`:
- **Section "Learning":**
  - `Toggle("Learn from my adjustments", isOn: $model.settings.learnSplits)`
  - `Toggle("Restore last order", isOn: $model.settings.splitRestoresOrder)`, with footer "Off: windows keep their current order and take their app's learned size."
  - `Picker("Empty space when order changes", …)`: "Stays in place" / "Follows its neighbour"
  - `splitGapWhenGrowing` has no effect until 1b's editor, so it gets no control here. 1b adds it beside the editor.
- **One section per display key**, titled with `SplitLabel.display`:
  - A row per split: `SplitLabel.apps(key)` and "Learned \(updated, style: .date)", plus a `Button("Forget")` calling `SplitMemory.forget`.
  - Footer when empty: "Nothing learned yet. Tile a display and adjust the windows by hand, or choose Remember Split from the menu bar."
- **`Button("Forget All…", role: .destructive)`** with a `confirmationDialog`: "Forget all learned splits? Tile will use equal shares again." / "Forget All".
- **`ResetSection(keeps: "Keeps your learned splits.")`**, which resets the three settings shown to their defaults.

- [ ] **Step 1: Implement `SplitsPane`** (≤ 300 lines; extract a `SplitRow` view if needed) and the `SettingsView` changes.
- [ ] **Step 2: Build the app.** Expected: `build exit 0`, no new warnings in the touched files.
- [ ] **Step 3: Commit.** `git commit -m "feat(settings): Splits pane"`

### Task 8: Verification and PR

**Files:**
- Modify: `README.md`:
  - Add a `tessera remember` line to the CLI section.
  - Change "⌘1–9 switches panes (…)" to the new order: General, Excluded Apps, Shortcuts, Cycles, Splits, Displays, Ring, Overlay, Motion; About ⌘0.

- [ ] **Step 1: Run the full core suite.** Expected: `Test run with N tests … passed`, where N = 282 + the new tests.
- [ ] **Step 2: Build the signed app in the user's terminal**, so the Accessibility grant survives:
  ```bash
  pkill -x Tessera; open "$(TESSERA_DERIVED_DATA=~/Library/Caches/tessera-build/dd-learned-splits scripts/build-app.sh | tail -1)"
  ```
- [ ] **Step 3: Manual checks (the user drives; record each result).**
  1. Tile two Chrome windows (nothing else open) and drag to about 30 / 70. Within about 1 s the message "Learned split · Google Chrome ×2 · …" appears.
  2. Tile again: 30 / 70 returns, and the message ends "· your split".
  3. Undo once: the windows return to their previous frames, and **no** new "Learned" message appears. Tile again, then Ring-snap one Chrome window to a half: again no "Learned" message.
  4. Relaunch Tessera and Tile: 30 / 70 again.
  5. Leave a strip on the right, wait, Tile: the strip returns.
  6. Swap the two apps' positions and Tile, with "Empty space" on each setting; compare against the spec.
  7. Arrange a 2×2 grid and choose Remember Split from the menu bar: "Remembered split · …". Then `tessera remember` in Terminal gives the same.
  8. Overlap two windows and Remember: the message says the windows overlap.
  9. Settings → Splits (⌘5): rows listed. Forget one → Tile is equal again. ⌘0 opens About.
- [ ] **Step 4: Commit the README**, push the branch and open the PR (title "feat: learned splits (1a engine)"), with test counts and manual results in the body.
