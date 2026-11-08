# In-app Help, Phase 1: Coach Overlay for Tile and Splits

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** after a Tile, a hand adjustment or a learned split, Tessera explains on screen what happened. It dims the display, spotlights the windows involved and shows a card that walks "what happened → try this → what that did". The coach also opens on request with ⌃⌥/ or **What Just Happened?** in the menu bar.

**Architecture:**
- **Pure logic in `TesseraCore/Help/`:** the event model, a 10-event journal, the auto-show policy, the copy and steps for each moment, and the spotlight geometry. All of it is unit tested.
- **The app layer records events:**
  - `CommandExecutor` (tile, forget) and `SplitWatcher` (neighbours followed, split learned or not learned) emit `HelpEvent`s.
  - `HelpCenter` decides what to show.
  - `CoachController` draws a mouse-transparent dim panel and a clickable card panel.
- **Every command carries a `CommandSource`,** so scripts never dim the screen.

**Tech Stack:** Swift 6, macOS 15, AppKit plus Core Animation (dim panel), SwiftUI in `NSHostingView` (card), Swift Testing (`import Testing`) in `Packages/TesseraCore/Tests/TesseraCoreTests`.

**Spec:** `docs/superpowers/specs/2026-11-07-in-app-help-design.md`. Phase 1 is "Order of work" step 1. Phases 2–5 (onboarding steps, guide, remaining moments, habit tips) get their own plans.

## Global Constraints

- **New Swift files stay under 300 lines.**
  - `Coordinator.swift` must not grow past 501 lines, and `CommandExecutor.swift` past 299.
  - `SplitWatcher.swift` must stay under 300.
- **Ring and preview panels stay non-activating and `ignoresMouseEvents = true`.** Only the coach card panel takes clicks, and AGENTS.md records that exception (Task 11).
- **Visible copy:** Australian English, no exclamation marks, precise and quiet (`docs/PRODUCT.md`, `docs/DESIGN.md`).
- **Auto-shown coach:**
  - never becomes key, never takes focus, never swallows a key
  - closes on a button, after 12 s untouched (step 1 only), on Esc observed passively, or when another app activates
- **On-request coach** (⌃⌥/, menu): may become key. Tab, Return and Esc work in it.
- **Only interactive sources auto-show:** `.ring`, `.hotkey`, `.menu`, `.hand`. `.automation` and `.coach` are journalled only.
- **Comfort:**
  - Reduce Motion: no pulse, fades only.
  - Colours come from the theme (`Theme.accentHex`).
  - VoiceOver reads the card.
- **Independent:** never read another window manager's source.
- **Tests:** `swift test --package-path Packages/TesseraCore --scratch-path ~/Library/Caches/tessera-build/core-help`
- **App build:** `TESSERA_DERIVED_DATA=~/Library/Caches/tessera-build/dd-help scripts/build-app.sh`
- **Before each commit that touches Swift in `Tessera/`:** run `/tessera-verify` (per CLAUDE.md).

## Review Focus

1. **The person keeps typing in their app while an auto-shown step 1 is up.** Every keystroke still reaches their app, and the coach fades on the first keyDown (Task 10 manual check).
2. **A window closed or an app quit between the event and a card button** (Tile Evenly Instead, Undo). The action checks the display still holds the event's `SplitKey`. If not, the card says "These windows have changed since then." and moves nothing (Task 11 manual check, pure helper tested in Task 3).
3. **Undo after the very first learn (no previous split).** Restoring `nil` forgets the key, and Tile then gives equal shares (Task 2 test).
4. **Restoring a split when `learnedSplits` is at capacity (50).** The count stays 50 and no other key is dropped (Task 2 test).
5. **Duplicate apps (two Chrome windows) in copy.** Names read "Chrome, Chrome and Codex", and share words still line up with on-screen order (Task 4 test).

---

### Task 1: Help settings and the ⌃⌥/ default

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/HelpSettings.swift`
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Model/Settings.swift` (add `help` after `updates`)
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Model/Command.swift`: add `case explain` and `case forgetSplit(display: DisplaySelector)` after `rememberSplit`, plus the default binding. The app target won't compile again until Task 7 handles the new cases. Only the core package is built until then.
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Model/MenuBarItems.swift` (add `explain = true`)
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Settings/SettingsStore.swift` (`decode` applies the offer)
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/HelpSettingsTests.swift`

**Interfaces:**
- Produces:
  - `public struct HelpSettings: Codable, Equatable, Sendable { public var autoShow = true; public var seenMoments: Set<String> = []; public var explainHotkeyOffered = false }`
  - `TesseraSettings.help: HelpSettings`
  - `MenuBarItems.explain: Bool`
  - `public enum HelpDefaults { public static let explainHotkey = Hotkey(keyCode: 44, modifiers: [.control, .option]); public static func offeringExplainHotkey(_ s: TesseraSettings) -> TesseraSettings }`

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct HelpSettingsTests {
    @Test func oldFileWithoutHelpDecodesWithDefaults() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        json.removeValue(forKey: "help")
        let (s, _) = try SettingsStore.decode(JSONSerialization.data(withJSONObject: json))
        #expect(s.help.autoShow)
        #expect(s.help.seenMoments.isEmpty)
    }
    @Test func offerAddsExplainWhenFree() {
        var s = TesseraSettings.defaults
        s.hotkeys.removeAll { $0.id == "explain" }
        let out = HelpDefaults.offeringExplainHotkey(s)
        #expect(out.hotkeys.filter { $0.id == "explain" }.count == 1)
        #expect(out.help.explainHotkeyOffered)
    }
    @Test func offerSkipsWhenChordTaken() {
        var s = TesseraSettings.defaults
        s.hotkeys.removeAll { $0.id == "explain" }
        s.hotkeys.append(HotkeyBinding(id: "mine", hotkey: HelpDefaults.explainHotkey, command: .undo))
        let out = HelpDefaults.offeringExplainHotkey(s)
        #expect(!out.hotkeys.contains { $0.id == "explain" })
        #expect(out.help.explainHotkeyOffered)
    }
    @Test func offerNeverReaddsAfterRemoval() {
        var s = TesseraSettings.defaults
        s.hotkeys.removeAll { $0.id == "explain" }
        s.help.explainHotkeyOffered = true
        #expect(!HelpDefaults.offeringExplainHotkey(s).hotkeys.contains { $0.id == "explain" })
    }
    @Test func freshDefaultsHoldExplainOnce() {
        let out = HelpDefaults.offeringExplainHotkey(.defaults)
        #expect(out.hotkeys.filter { $0.id == "explain" }.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests.** Expected: FAIL (`HelpSettings` / `HelpDefaults` undefined).
- [ ] **Step 3: Implement.**
  - Add `HelpSettings`, `HelpDefaults` and `TesseraSettings.help = HelpSettings()`. No schema bump: migration fills missing nested keys.
  - Add `MenuBarItems.explain = true`.
  - Append `HotkeyBinding(id: "explain", hotkey: HelpDefaults.explainHotkey, command: .explain)` to `HotkeyBinding.defaults`, before `open-settings`.
  - In `SettingsStore.decode`, return `HelpDefaults.offeringExplainHotkey(settings)`.
  - The offer adds the default binding only when `!help.explainHotkeyOffered` and no binding has `hotkey == explainHotkey`. It always sets `explainHotkeyOffered = true`.
- [ ] **Step 4: Run the full core suite.** Expected: PASS, including the existing `SettingsMigrationTests` and `SettingsStoreTests`. Update a test only if it counts default hotkeys; the count becomes +1.
- [ ] **Step 5: Commit** `feat(help): help settings and ⌃⌥/ default`.

### Task 2: Restoring a split

**Files:**
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Splits/SplitMemory.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/SplitMemoryTests.swift`

**Interfaces:**
- Produces: `public static func restore(_ previous: LearnedSplit?, for key: SplitKey, in splits: [LearnedSplit]) -> [LearnedSplit]`. It forgets `key`, then upserts `previous` when it isn't nil, keeping `previous.updated` unchanged.

- [ ] **Step 1: Write the failing tests** (use the suite's `split(_:display:at:)` helper):
  - `restoreNilForgetsKey`: `restore(nil, for: k, in: [split(["a","b"])])` is empty.
  - `restorePutsPreviousBack`: after an upsert of a newer split for the same key, `restore(old, …)` gives back `old` with `old.updated` unchanged.
  - `restoreAtCapacityKeepsOthers`: 50 splits for distinct keys. Restoring the previous version of key #10 leaves the count at 50 and keeps all other 49 keys.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `restore` as `forget` + `upsert`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(splits): restore a previous split`.

### Task 3: Events, sources and the journal

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/HelpEvent.swift`
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/HelpJournal.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/HelpJournalTests.swift`

**Interfaces:**
- Produces:

```swift
public enum CommandSource: String, Codable, Sendable { case ring, hotkey, menu, hand, coach, automation
    public var isInteractive: Bool }                       // ring, hotkey, menu, hand
public enum HelpEventKind: Equatable, Sendable {
    case tiled(usedSplit: Bool)
    case tiledEvenly(hasSplit: Bool)
    case tilePartial(moved: Int, total: Int, stuck: [String])
    case neighboursFollowed(changed: String, followers: [String])
    case splitLearned
    case splitNotLearned(reason: String)
    case splitForgotten
}
public enum CoachMoment: String, CaseIterable, Sendable {
    case tiledWithSplit, tiledEqual, tiledEvenly, tilePartial, neighboursFollowed, splitLearned, splitNotLearned, splitForgotten
}
public struct HelpEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var kind: HelpEventKind
    public var source: CommandSource
    public var date: Date
    public var displayKey: String          // DisplayID.storageKey
    public var displayName: String         // "CHG90", or "this display"
    public var apps: [String]              // app names in on-screen order (left→right, top→bottom on portrait)
    public var frames: [CGRect]            // AppKit global, same order as apps
    public var usable: CGRect              // GridGeometry.usableFrame of the display
    public var portrait: Bool
    public var key: SplitKey?
    public var split: LearnedSplit?        // split in effect after the event (used or just learned)
    public var previousSplit: LearnedSplit? // for splitLearned / splitForgotten: what Undo restores
    public var moment: CoachMoment { get }
    public var isNonEvent: Bool { get }     // tilePartial, splitNotLearned
    public func stillMatches(_ current: SplitKey?) -> Bool   // key != nil && key == current
}
public struct HelpJournal: Sendable {
    public init()
    public static let capacity = 10
    public private(set) var events: [HelpEvent]   // oldest first
    public mutating func record(_ event: HelpEvent)
    public var latest: HelpEvent? { get }
    public func event(before id: UUID) -> HelpEvent?
    public func event(after id: UUID) -> HelpEvent?
    public func lastTile(for key: SplitKey, before id: UUID) -> HelpEvent?   // kinds .tiled only
}
```

`HelpEvent.init` takes every stored property, with `id: UUID = UUID()` and `date: Date = Date()` as defaults.

- [ ] **Step 1: Write the failing tests.**
  - `capacityDropsOldest`: record 11 events, the first one is gone, and `latest` is the 11th.
  - `beforeAfterNavigate`: `event(before:)` and `event(after:)` walk the journal and return nil at either end.
  - `lastTileSkipsOtherKeysAndKinds`.
  - `momentMapping`: `.tiled(usedSplit: true)` → `.tiledWithSplit`, `.tiled(false)` → `.tiledEqual`, and so on for every kind.
  - `nonEvents`: true only for `.tilePartial` and `.splitNotLearned`.
  - `stillMatches`: true for an equal key, false for nil or a different key.
  - `interactiveSources`: true for ring, hotkey, menu and hand; false for coach and automation.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(help): events and journal`.

### Task 4: Copy and steps for each moment

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/CoachCopy.swift`
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/CoachScript.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/CoachScriptTests.swift`

**Interfaces:**
- Consumes: `HelpEvent` (Task 3).
- Produces:

```swift
public enum CoachCopy {
    public static func list(_ names: [String]) -> String                 // "A", "A and B", "A, B and C"
    public static func share(_ fraction: Double) -> String               // see table below
    public static func equalShare(_ count: Int) -> String                // 2 "half", 3 "a third", 4 "a quarter", 5 "a fifth", 6 "a sixth", else "an equal share"
    public static func shares(apps: [String], frames: [CGRect], usable: CGRect, portrait: Bool) -> String
    public static func day(_ date: Date) -> String                       // "7 Nov", en_AU, current time zone
}
public enum CoachAction: Equatable, Sendable {
    case next, done, skip, tileEvenly, undoSplitChange, forgetSplit, undoMove, openSplitsSettings, tileAll
    public var label: String   // "Show Me More", "Done", "Skip", "Tile Evenly Instead", "Undo", "Forget This Split", "Undo", "Open Splits Settings", "Tile All Windows"
}
public enum CoachSpotlight: Equatable, Sendable { case windows, seam }
public struct CoachStep: Equatable, Sendable {
    public var title: String
    public var body: String
    public var actions: [CoachAction]       // first is the primary (accent) button
    public var spotlight: CoachSpotlight
    public var waitsForLearn: Bool          // advance when a .splitLearned for the same key arrives
}
public enum CoachScript {
    public static func steps(for event: HelpEvent) -> [CoachStep]
    /// After Forget This Split: one step, actions [.undoSplitChange, .done].
    public static func forgotten(_ event: HelpEvent) -> CoachStep
    /// Shown instead of running an action when the display no longer holds the event's apps.
    public static let changed = "These windows have changed since then."
}
```

**`share` table:** take the extent along the split axis divided by the usable extent. Use the nearest of 1/4 "a quarter", 1/3 "a third", 1/2 "half", 2/3 "two thirds", 3/4 "three quarters" when within 0.03; otherwise `"\(Int((f*100).rounded()))%"`.

**`shares`:** with ≥3 windows where every window after the first has the same word, write `"<first> <w1>, the others <w> each"`. Otherwise write `"<app> <w>"` pairs joined with `", "`.

**Exact copy that the tests pin** (the spec fixes it; write the other moments in the same voice, from `docs/USER-GUIDE.md` §6–7):

| Event | Step | Title | Body | Actions |
|---|---|---|---|---|
| `.tiled(usedSplit: true)` | 1 | `Tiled with your split` | `You taught Tessera this split for {list(apps)} on {day(split.updated)}: {shares}. Without it, each would get {equalShare(n)}.` | next, tileEvenly, done |
| | 2 | `Try it: drag this edge` | `Make {apps[0]} narrower. {list(apps.dropFirst())} will move with it.` (spotlight `.seam`, `waitsForLearn`) | skip |
| | 3 | `{list(apps.dropFirst())} followed` | `Tessera saved this as your new split for these {n} apps. Press ⌃⌥T any time to get it back.` | done, undoSplitChange |
| `.tiled(usedSplit: false)` | 1 | `Tiled in equal shares` | `Tessera has no split for {list(apps)} on {displayName} yet, so each got {equalShare(n)}.` | next, done |
| | 2–3 | same as above, but step 3's body starts `Tessera saved this as your split for these {n} apps.` | | |
| `.tiledEvenly(hasSplit: true)` | 1 | `Tiled evenly` | `Each window got {equalShare(n)}. Your split for these apps is kept for the next Tile All Windows (⌃⌥T), and adjustments now aren't saved.` | done |
| `.splitLearned` | 1 | `Saved as your split` | `Next time {list(apps)} are on {displayName}, Tile All Windows (⌃⌥T) puts them back like this.` | done, forgetSplit |
| `.splitNotLearned(r)` | 1 | `Not saved as a split` | `{r}. Tile All Windows (⌃⌥T) lines the windows up.` | tileAll, done |

- Step 2 needs n ≥ 2. A one-window tile gets step 1 only, with actions `[.done]`.
- `.tilePartial`, `.neighboursFollowed` and `.splitForgotten` each get one step. Their copy is the implementer's, with the actions listed below:
  - `tilePartial`: undoMove, done
  - `neighboursFollowed`: done, undoMove, openSplitsSettings
  - forgotten: undoSplitChange, done

- [ ] **Step 1: Write the failing tests** with a fixture event: apps `["Dia","Claude","Codex"]`, frames at widths 1/2, 1/4, 1/4 of usable `CGRect(x:0,y:0,width:3840,height:1050)`, and `split.updated = Date(timeIntervalSince1970: 1_794_052_800)` (7 Nov 2026, midday UTC). Assert:
  - `steps(for: tiledWithSplit)[0].body == "You taught Tessera this split for Dia, Claude and Codex on 7 Nov: Dia half, the others a quarter each. Without it, each would get a third."`
  - The steps count is 3, `steps[1].waitsForLearn`, `steps[1].spotlight == .seam`, and `steps[2].actions == [.done, .undoSplitChange]`.
  - `CoachCopy.list(["Chrome","Chrome","Codex"]) == "Chrome, Chrome and Codex"` (Review Focus 5).
  - `share(0.5) == "half"`, `share(0.34) == "a third"`, `share(0.41) == "41%"`, `equalShare(7) == "an equal share"`.
  - Mixed shares: widths 1/2, 1/3, 1/6 give `"Dia half, Claude a third, Codex 17%"`.
  - A one-window tiled event gives one step whose actions are `[.done]`.
  - `splitNotLearned(reason: "Windows overlap")` body starts `"Windows overlap."`.
  - No step title or body anywhere contains `"!"`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(help): coach copy and steps`.

### Task 5: Auto-show policy

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/CoachPolicy.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/CoachPolicyTests.swift`

**Interfaces:**
- Consumes: `HelpEvent`, `HelpSettings`.
- Produces:

```swift
public enum CoachPresentation: Equatable, Sendable { case full, light }
public struct CoachContext: Sendable {
    public var ringOpen: Bool, mouseDown: Bool, secondsSinceTyping: Double, coachShowing: Bool, now: Date
    public init(ringOpen: Bool, mouseDown: Bool, secondsSinceTyping: Double, coachShowing: Bool, now: Date)
}
public struct CoachPolicy: Sendable {
    public init()
    /// nil = don't show on its own. Records per-day non-event reasons it lets through.
    public mutating func presentation(for event: HelpEvent, help: HelpSettings,
                                      previousTile: HelpEvent?, context: CoachContext) -> CoachPresentation?
}
```

**Rules, in order:**
1. `!event.source.isInteractive` → nil.
2. `!help.autoShow` → nil.
3. `ringOpen || mouseDown || coachShowing` → nil.
4. `source == .hand && secondsSinceTyping < 2` → nil.
5. `event.moment.rawValue` not in `help.seenMoments` → `isNonEvent ? .light : .full`.
6. `.tilePartial` → `.light`.
7. `.splitNotLearned(r)` → `.light` if `r` hasn't been let through on the same calendar day (`Calendar.current.isDate(_:inSameDayAs:)`), else nil.
8. `.tiled(usedSplit: u)` where `previousTile` is `.tiled(usedSplit: !u)` → `.light`.
9. Otherwise nil.

- [ ] **Step 1: Write a failing test per rule:**
  - `automationNeverShows`, `coachSourceNeverShows`, `autoShowOffNeverShows`
  - `ringOpenSuppresses`, `mouseDownSuppresses`
  - `handTypingSuppresses`, and `hotkeyTypingDoesNot` (a hotkey source with `secondsSinceTyping: 0.1` still shows the first time)
  - `firstTimeFull`, `firstTimeNonEventLight`, `seenGivesNil`
  - `partialAlwaysLight`
  - `notLearnedOncePerDay` (same reason twice on one day → `.light` then nil; the next day → `.light`)
  - `usedSplitFlipIsLight`
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(help): auto-show policy`.

### Task 6: Spotlight geometry

**Files:**
- Create: `Packages/TesseraCore/Sources/TesseraCore/Help/CoachGeometry.swift`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/CoachGeometryTests.swift`

**Interfaces:**
- Produces:

```swift
public enum CoachGeometry {
    public static let inset: CGFloat = 4          // spotlight grows by this around each window
    /// The shared edge between frames[0] and frames[1] in on-screen order, as an 8 pt wide (tall on portrait) rect;
    /// nil when they don't face each other within `gap + 2`.
    public static func seam(_ frames: [CGRect], portrait: Bool, gap: CGFloat) -> CGRect?
    /// Card origin (AppKit, bottom-left) beside `target`: below it if it fits, else above, else right, else left,
    /// then clamped so the card sits ≥ 12 pt inside `screen`.
    public static func cardOrigin(size: CGSize, target: CGRect, screen: CGRect) -> CGPoint
}
```

- [ ] **Step 1: Write the failing tests:**
  - `seamBetweenSideBySide`: frames 0…1920 and 1928…3840 with gap 8 give a seam with midX 1924 and width 8.
  - `seamNilWhenApart`.
  - `seamPortraitIsHorizontal`.
  - `cardStaysInsideScreen`: a target at the screen's bottom-right corner gives a card frame inset ≥ 12 on every side.
  - `cardPrefersBelow`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(help): spotlight geometry`.

### Task 7: `explain` and `forgetSplit` commands

**Files:**
- (The `Command` cases already exist from Task 1.)
- Modify: `Packages/TesseraCore/Sources/TesseraCore/Commands/CommandParser.swift`: verbs `explain`, `forget [--display D]`; usage lines; URL refuses `forget`
- Modify: `Tessera/UI/ShortcutsPane.swift`: `Kind` cases `explain = "What just happened"` and `forgetSplit = "Forget split"`, in the three switches and `summary`
- Modify: `Tessera/App/CommandExecutor.swift`: `var onExplain: (() -> Void)?`; route `.explain` and `.forgetSplit` to the Splits extension
- Modify: `Tessera/App/CommandExecutor+Splits.swift`: `func forgetSplit(_ selector: DisplaySelector) async throws(Failure) -> CommandResult`
- Test: `Packages/TesseraCore/Tests/TesseraCoreTests/CommandParserTests.swift`

**Interfaces:**
- Produces:
  - `Command.explain`
  - `Command.forgetSplit(display:)`
  - `CommandExecutor.onExplain`
  - Forget's result message: `"Forgot split · \(SplitLabel.apps(key))"`
  - Its failure: `"No split for these apps"`

- [ ] **Step 1: Write the failing parser tests:**
  - `parse(arguments: ["explain"]) == .explain`
  - `["forget"]` → `.forgetSplit(display: .current)`
  - `["forget","--display","2"]` → `.forgetSplit(display: .index(2))`
  - `parse(url: tessera://explain) == .explain`
  - `parse(url: tessera://forget)` throws `"'forget' is not available via URL"`
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement the parser and model cases.**
  - Executor: `case .explain: onExplain?(); return .success`.
  - `case .forgetSplit(let s): return try await forgetSplit(s)`. It looks up `SplitKey(found, on: display)` and throws if there's no stored split, otherwise `model.settings.learnedSplits = SplitMemory.forget(key, in:)`.
  - **Keep `CommandExecutor.swift` ≤ 299 lines:** move `.undo`'s 6-line body into `func undoLast() async throws(Failure)` in `CommandExecutor+Splits.swift`.
- [ ] **Step 4: Run** the core tests and `scripts/build-app.sh` (with `TESSERA_DERIVED_DATA`). Expected: PASS, and the build succeeds.
- [ ] **Step 5: `/tessera-verify`, then commit** `feat(help): explain and forget split commands`.

### Task 8: Command sources and executor events

**Files:**
- Modify: `Tessera/App/CommandBridge.swift`
  - `CommandExecuting.execute(_ command: Command, source: CommandSource) async -> CommandResult`
  - `CommandBridge.execute(_ command: Command, source: CommandSource = .automation)`
- Modify: `Tessera/App/CommandExecutor.swift`
  - `execute(_:source:)` and `run(_:source:)`
  - `var onEvent: ((HelpEvent) -> Void)?`
  - move `tile(_:evenly:)` out to the Splits extension (frees about 35 lines)
- Modify: `Tessera/App/CommandExecutor+Splits.swift`: `tile(_ selector: DisplaySelector, evenly: Bool, source: CommandSource)`; it emits events, and forget emits `.splitForgotten`
- Create: `Tessera/Help/HelpEvent+App.swift`
- Modify: `Tessera/App/Coordinator.swift`
  - `run(_ command: Command, source: CommandSource)`, where hotkey feedback means `source == .hotkey`
  - call sites: `.command` → `.hotkey`, tap-to-tile → `.ring`, `undoLast` → `.menu` (fold it to one line to stay ≤ 501)
  - `var isRingOpen: Bool { session != nil }`
- Modify: `Tessera/App/AppDelegate.swift`: status item `run` → `.menu`, URL → `.automation`

**Interfaces:**
- Consumes: `CommandSource`, `HelpEvent` (Task 3).
- Produces:
  - `extension HelpEvent { @MainActor static func make(kind: HelpEventKind, source: CommandSource, display: DisplayContext, group: [(window: WindowRef, frame: CGRect)], split: LearnedSplit?, previous: LearnedSplit?) -> HelpEvent }`. It fills app names (`NSRunningApplication(processIdentifier:).localizedName ?? bundleID ?? "Untitled"`), `displayName` (the `NSScreen.localizedName` whose frame equals `display.frame`, else `"this display"`), `usable` and `portrait`. It first sorts `group` into on-screen order (by `minX`, or by `maxY` descending on portrait), because the watcher's `visibleWindows` order isn't on-screen order.
  - `CommandExecutor.onEvent`.

- [ ] **Step 1: Thread `source` through:**
  - Every non-Coordinator caller (socket, AppleScript, intents) keeps compiling unchanged through the `.automation` default.
- [ ] **Step 2: Emit events in `tile`, after `mergeMoves`:**
  - `moved < n` → `.tilePartial(moved:total:stuck:)`, where `stuck` lists the app names whose `place` didn't return `.applied`.
  - otherwise `.tiled(usedSplit: learned)`, or `.tiledEvenly(hasSplit: SplitMemory.lookup(key, …) != nil)` for evenly.
  - `split` is the looked-up split.
- [ ] **Step 3: Build.** Expected: succeeds. `wc -l Tessera/App/Coordinator.swift Tessera/App/CommandExecutor.swift` must show ≤ 501 and ≤ 299.
- [ ] **Step 4: Manual check** with a temporary `onEvent = { print($0.kind) }` from Xcode or the console. ⌃⌥T prints `.tiled`, and `tessera tile` from the CLI prints a source of `.automation`. Remove the print.
- [ ] **Step 5: `/tessera-verify`, then commit** `feat(help): command sources and tile events`.

### Task 9: Watcher events

**Files:**
- Create: `Tessera/Services/SplitWatcher+Save.swift`: move `save(_:display:onlyIfChanged:)` here first (make `model` internal), so `SplitWatcher.swift` has room
- Modify: `Tessera/Services/SplitWatcher.swift`: `var onHelpEvent: ((HelpEvent) -> Void)?`; emit from `reflow` and `learnNow`
- Modify: `Tessera/Services/SplitWatchers.swift`: `onHelpEvent` with the same `didSet` forwarding as `onLearned`, also set in `watcher(for:)`

**Interfaces:**
- Consumes: `HelpEvent.make` (Task 8).
- Produces: `SplitWatchers.onHelpEvent`.

- [ ] **Step 1: Move `save`.** Build. Expected: succeeds with no behaviour change.
- [ ] **Step 2: In `reflow`, after `mergeMoves`, emit `.neighboursFollowed`:**
  - `changed`: the app of the first index whose frame differs from `before` and isn't in `moves`.
  - `followers`: the apps of `moves`.
  - `source: .hand`.
- [ ] **Step 3: In `learnNow`, replace the final `guard learns, case .success…` line.**
  - Read `let previous = SplitMemory.lookup(key, in: model.settings.learnedSplits)` before calling `save`.
  - On `.failure(r)`, emit `.splitNotLearned(reason: r.message)`.
  - On `.success((_, true))`, keep `onLearned?` and emit `.splitLearned` with `split` set to the new lookup and `previous` set to `previous`.
  - With `learns == false`, emit nothing.
- [ ] **Step 4: Build.** `wc -l Tessera/Services/SplitWatcher.swift` must be < 300.
- [ ] **Step 5: `/tessera-verify`, then commit** `feat(help): watcher events`.

### Task 10: Coach panels

**Files:**
- Create: `Tessera/Help/CoachController.swift`
  - owns, per display, one dim panel and one card panel
  - `present(step:index:count:event:display:presentation:keyable:)` and `dismiss()`. Callbacks are properties (see Produces).
- Create: `Tessera/Help/CoachDimView.swift`: layer-backed view
  - `CAShapeLayer` with `fillRule = .evenOdd` (the screen rect minus spotlight rects, black at 0.45 alpha)
  - a 2 pt outline in the theme accent
  - a seam layer with an opacity pulse (`CABasicAnimation`, 0.4 → 1, 0.9 s, autoreverses); none with Reduce Motion
- Create: `Tessera/Help/CoachCardView.swift`: SwiftUI card
  - title, body, "n of m", buttons (first is `.borderedProminent`)
  - footer "Don't show tips" (auto only), or ‹ › (on request)
  - VoiceOver: the container is `.accessibilityElement(children: .contain)`, labelled with the title

**Interfaces:**
- Consumes: `CoachStep`, `CoachGeometry`, `HelpEvent`, `CoachPresentation`, `Theme`.
- Produces:
  - `final class CoachController { var onAction: ((CoachAction) -> Void)?; var onClose: (() -> Void)?; var onBrowse: ((Int) -> Void)? /* -1 earlier, +1 later */; var onDontShow: (() -> Void)?; func present(…); func dismiss(); var isShowing: Bool }`
  - `CoachCardPanel: NSPanel` with `canBecomeKey` returning its `keyable` flag

**Panel rules:**
- **Dim panel:** reuse `OverlayController.makePanel(frame:)` (borderless, non-activating, `ignoresMouseEvents = true`), with `level = .statusBar`. **Light presentation draws no dim and no outline.**
- **Card panel:** `[.borderless, .nonactivatingPanel]`, `level = .popUpMenu`, `ignoresMouseEvents = false`, `becomesKeyOnlyIfNeeded = true`. Its hosting view overrides `acceptsFirstMouse` → true.
- **Spotlight:** `event.frames`, each grown by `CoachGeometry.inset`. With `.seam`, use the seam rect from `CoachGeometry.seam(event.frames, portrait:, gap: display.profile.gap)`.
- **Card placement:** `CoachGeometry.cardOrigin`.
- **Keys and focus:**
  - Keyable (on request): `makeKeyAndOrderFront`, and the card takes Tab, Return and Esc (Esc → `onClose`). On close, call `NSRunningApplication(processIdentifier: previousPID)?.activate()`.
  - Auto: `orderFrontRegardless`. While showing, a global `NSEvent` monitor for `.keyDown` (observe only) calls `onClose` on Esc, and on any key during a step whose `waitsForLearn == false`. A `didActivateApplicationNotification` for another app calls `onClose`. A 12 s timer on step 1 calls `onClose`, and hovering the card cancels it.
  - Remove every monitor and timer in `dismiss()`.
- **Fades:** 0.2 s on present and dismiss, `NSAnimationContext`.

- [ ] **Step 1: Build all three files.** Expected: succeeds, each file < 300 lines.
- [ ] **Step 2: Manual check from a temporary debug call** (`Coordinator` init, removed afterwards) presenting the fixture event from Task 4 on the main display. Check:
  - the dim and spotlight line up with real windows on both a Retina and a non-Retina display
  - clicks and drags pass through the dim to the real windows
  - the card buttons click without Tessera activating (the menu bar app name stays the front app's)
  - typing in TextEdit while the auto card shows: every character lands, and the card fades (Review Focus 1)
  - with Reduce Motion on, nothing pulses
- [ ] **Step 3: Run the `design-conformance-reviewer` agent** on `Tessera/Help/`. Fix its findings.
- [ ] **Step 4: `/tessera-verify`, then commit** `feat(help): coach overlay panels`.

### Task 11: HelpCenter, wiring, menu item and Settings

**Files:**
- Create: `Tessera/Help/HelpCenter.swift`: `@MainActor final class HelpCenter`
  - `init(model: SettingsModel, displays: DisplayService, windows: WindowService, presenter: WindowPresenter, showHUD: @escaping (String) -> Void, isRingOpen: @escaping () -> Bool)`
  - Owns its own `CoachController`, `HelpJournal` and `CoachPolicy`.
  - AppDelegate passes `coordinator.presenter`, `{ coordinator.showHUD($0) }` and `{ coordinator.isRingOpen }`. `Coordinator` exposes the display and window services to `HelpCenter` as `let displays` (already internal) and a new `var windowService: WindowService { windows }` (1 line, within the ≤ 501 budget after folding `undoLast`).
  - `func record(_ event: HelpEvent)`
  - `func explainLatest()`
- Create: `Tessera/UI/HelpSection.swift`
  - Settings › General section "Help": the toggle "Show tips when something new happens" (`help.autoShow`), and the button "Show Tips Again" (clears `seenMoments`)
  - footnote: "What Just Happened? (⌃⌥/) always works."
- Modify: `Tessera/UI/GeneralPane.swift`
  - include `HelpSection()`
  - menu bar toggle "What Just Happened?" bound to `menuBarItems.explain`
- Modify: `Tessera/App/StatusItemController.swift`: item "What Just Happened?" after the status line, running `.explain`, shown when `menuBarItems.explain`
- Modify: `Tessera/App/AppDelegate.swift`: create `HelpCenter` after the coordinator, and wire `executor.onEvent`, `executor.splitWatcher.onHelpEvent` and `executor.onExplain` to it
- Modify: `AGENTS.md`: append to the overlay rule: "Exception: the coach card panel (`Tessera/Help/CoachController`) takes clicks; its dim panel stays mouse-transparent, and an auto-shown card never becomes key."
- Modify: `docs/USER-GUIDE.md`: a new §8a "What Just Happened?", with the coach, ⌃⌥/, the menu item and the switch

**Behaviour HelpCenter owns** (these decide nothing the earlier tasks haven't defined):

- **`record`:**
  - If a tour is on a `waitsForLearn` step and the event is `.splitLearned` with the same `key`, advance to the next step. The new step's Undo uses this event's `previousSplit`.
  - Otherwise, append to the journal and ask `CoachPolicy` with `CoachContext`:
    - `ringOpen`: `isRingOpen()`
    - `mouseDown`: `NSEvent.pressedMouseButtons != 0`
    - `secondsSinceTyping`: `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)`
    - `coachShowing`: `coach.isShowing`
  - On a result, present step 0 and insert `moment.rawValue` into `model.settings.help.seenMoments`.
- **`explainLatest`:** present the journal's latest event as `.full` with `keyable: true`, and ‹ › browse the journal. With an empty journal, show the HUD "Nothing to explain yet".
- **Actions:**

  | Action | What it does |
  |---|---|
  | `.next` / `.skip` | next step (skip jumps past `waitsForLearn`) |
  | `.done` | close |
  | `.tileEvenly` | `.tileEvenly(display: .id(event.displayKey))` |
  | `.tileAll` | `.tileWindows(display: .id(event.displayKey))` |
  | `.undoMove` | `.undo` |
  | `.forgetSplit` | `.forgetSplit` for the event's key, then present `CoachScript.forgotten` |
  | `.undoSplitChange` | `SplitMemory.restore(previousSplit, for: key, in:)`, then `.tileWindows(display: .id(displayKey))` |
  | `.openSplitsSettings` | `presenter.showSettings(pane: .splits)` |

  - Every command action runs through `CommandBridge.execute(_, source: .coach)`.
  - Before any move or forget, read the display's current windows and check `event.stillMatches(SplitKey(current, on: display))`. If they don't match, replace the body with `CoachScript.changed` and keep only `.done` (Review Focus 2).
  - `.forgetSplit` from the card forgets `event.key` directly with `SplitMemory.forget`, not by display, so ‹ › never forgets the wrong split.
- **Don't show tips:** sets `help.autoShow = false` and closes.

- [ ] **Step 1: Build.** Expected: succeeds, and `HelpCenter.swift` is < 300 lines (split action handling into `HelpCenter+Actions.swift` if not).
- [ ] **Step 2: Run the `swift-concurrency-reviewer` agent** on `Tessera/Help/`, the `Services` changes and `CommandBridge`. Fix its findings.
- [ ] **Step 3: Hands-on check** on the CHG90 with Dia, Claude and Codex. Use "Show Tips Again" first.
  1. ⌃⌥T with no split → "Tiled in equal shares", full coach.
  2. Show Me More → seam pulses → drag Dia's edge → step 3 appears once the split is learned.
  3. Undo in step 3 → the previous split is restored (here: none), and the windows retile equally.
  4. Learn a split, ⌃⌥T again → no auto coach (seen). ⌃⌥/ → "Tiled with your split… on 7 Nov…", and it takes Tab and Return.
  5. Tile Evenly Instead → equal thirds, and Settings › Splits still lists the split.
  6. `tessera tile` from Terminal → no coach. ⌃⌥/ explains it.
  7. Overlap two windows and drag one → the light card "Not saved as a split" appears once that day.
  8. Close Codex while the step 1 card is open, then click Tile Evenly Instead → "These windows have changed since then.", and nothing moves.
- [ ] **Step 4: `/tessera-verify`, then commit** `feat(help): What Just Happened coach`.

---

## Not in this phase (later plans)

- **Phase 2:** onboarding steps 5–8 (spec part 6).
- **Phase 3:** the Live guide window, "?" buttons, and Show Me on My Screen (part 3).
- **Phase 4:**
  - ring, cycle, column, display-move, undo and trigger-ignored moments
  - practice windows (part 4)
  - detecting drags on unwatched (overlapping) windows
- **Phase 5:** habit tips (part 5), with their settings `habitTips`, `lastTipDate` and `habitCounts`.
- **Deviation to confirm with Sir:** split restore lives in the coach's **Undo** (and the Undo after Forget). Plain ⌃⌥Z stays window-only, because a learn isn't a window move, so a ⌃⌥Z step for it would move nothing visible. The spec's "Split undo" note in `WindowUndoHistory` is therefore not built.
