# Tessera Milestone 2 Implementation Plan (keyboard + automation)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make every Tessera capability reachable from the keyboard and from automation (hotkeys, ring nav keys, URL, CLI, AppleScript, App Intents), all through one `Command` language.

**Architecture:**
- **TesseraCore** (pure, unit-tested) gets:
  - command parsing
  - target and display resolution
  - keyboard navigation
  - cycles
  - hotkey matching
  - the settings v2 migration
- **App** gets a `CommandExecutor` behind `CommandBridge`, which every surface calls.

**Spec:** `docs/superpowers/specs/2026-10-03-tessera-milestone2-keyboard-automation-design.md`. Read it together with the M1 spec.

## Global Constraints

### Carried over from M1
- macOS 15.
- Swift 6 with complete strict concurrency.
- No third-party dependencies.
- No force-unwraps, `try!` or `as!` on system calls.
- Files under 500 lines.
- Private APIs via `dlsym` only.
- Never copy from `loop/`.

### Commands
- **Every `swift`, `xcodebuild` and `xcodegen` command runs with Bash `dangerouslyDisableSandbox: true`.**
- **Build output lives outside iCloud.** For your track letter `$T`:
  - `swift test --package-path Packages/TesseraCore --scratch-path ~/Library/Caches/tessera-build/core-$T`
  - `xcodegen generate && xcodebuild -project Tessera.xcodeproj -scheme Tessera -derivedDataPath ~/Library/Caches/tessera-build/dd-$T build`
- In worktrees, plain `git` is refused. Use `git -C "<worktree path>" …`.
- Commit messages end with `Co-Authored-By: <your model> <noreply@anthropic.com>`.

### Contract
The contract lives in `Packages/TesseraCore/Sources/TesseraCore/Model/Command.swift` and `Model/Settings.swift`, plus `Tessera/App/CommandBridge.swift`. **Do not edit these files.** If something needs to change, use SendMessage to tell the coordinator.

### Shared language rules
- Span columns are 1-based. Negative numbers count from the right.
- Display order is by `frame.minX`, then `frame.minY`.
- Spans and other targets are clamped to the display's column count.

## Review Focus

Each of these needs a test in the track named.

1. **Out-of-range columns.** `cols=0`, `cols=9` on a 2-column display, and `cols=-5..-1` on a 3-column display must clamp to valid columns, never crash, and never produce an empty span. (Track G)
2. **Malformed URL or CLI input.** Unknown verbs, `cols=a-b`, a missing value, or `band=middle` must return `CommandParseError.invalid` with a message that names the bad part. (Track G)
3. **Hotkeys with extra modifiers.** A ⌃⌥⇧← keypress must not trigger the ⌃⌥← binding. Matching is exact. (Track H)
4. **Pressing a cycle on a different window.** The cycle restarts at step 0. (Track H)
5. **A v1 file from the M1 build.** It migrates to v2, keeps the user's display overrides, and writes a backup. (Track H)

## Parallel tracks
The coordinator has already committed **Track 0′**: the contract types, settings fields, `CommandBridge` and the project.yml URL and AppleScript keys. G and H work on the pure core. I, J and K work on the app, in parallel.

---

### Track G: CommandParser and resolvers (core; agent "commands")

**Files:**
- `Sources/TesseraCore/Commands/CommandParser.swift`
- `Sources/TesseraCore/Commands/Resolvers.swift`
- `Tests/CommandParserTests.swift`
- `Tests/ResolverTests.swift`

**Produces:**
- `enum CommandParseError: Error, Equatable { case invalid(String) }`
- `enum CommandParser`:
  - `static func parse(url: URL) throws -> Command`
  - `static func parse(arguments: [String]) throws -> Command` (argv without the program name)
  - `static let usage: String`
- `enum DisplayResolver`:
  - `static func ordered(_ displays: [DisplayContext]) -> [DisplayContext]`
  - `static func resolve(_ s: DisplaySelector, displays: [DisplayContext], windowFrame: CGRect?, cursor: CGPoint) -> DisplayContext?`
  - `static func step(_ s: DisplayStep, from: DisplayContext, displays: [DisplayContext]) -> DisplayContext?` (wraps around)
- `enum TargetResolver`:
  - `static func span(for target: Target, display: DisplayContext) -> ColumnSpan?` (1-based or negative → 0-based clamped ColumnSpan; nil for `.action`)
  - `static func frame(for target: Target, display: DisplayContext, current: CGRect) -> CGRect` (uses GridGeometry)
  - `static func relocate(span: ColumnSpan, from: DisplayContext, to: DisplayContext) -> ColumnSpan` (keeps the column ratio)

**Syntax:** exactly as in M2 spec §2.

- [x] Write tests:
  - every URL and CLI example in the spec
  - Review Focus 1 and 2
  - `-2..-1` on 5 columns → `3...4`
  - `index(2)` uses left-to-right order
  - `next` from the last display wraps to the first
  - relocate: columns 2–3 of 5 → columns 2–3 of 6, using the rule `round(start*to/from)…max(start, round((end+1)*to/from)-1)`
- [x] Watch them fail, implement, watch them pass, commit `feat(commands): parser and resolvers`.

---

### Track H: Navigation, cycles, hotkeys, trigger, migration (core; agent "keyboard-core")

**Files:**
- `Sources/TesseraCore/Keyboard/KeyNavigator.swift`
- `Sources/TesseraCore/Keyboard/CycleTracker.swift`
- `Sources/TesseraCore/Keyboard/HotkeyTable.swift`
- `Sources/TesseraCore/Settings/SettingsMigration.swift`
- edits to `Trigger/TriggerMachine.swift`, `Settings/SettingsStore.swift`, `Settings/SettingsValidation.swift` and their tests
- new tests: `KeyNavigatorTests`, `CycleTrackerTests`, `HotkeyTableTests`, `SettingsMigrationTests`

**Produces:**
- `struct NavState: Equatable, Sendable`
  - Fields: `displayIndex: Int` (into `DisplayResolver`-ordered displays; until G merges, sort by minX then minY inline), `columns: ClosedRange<Int>` (0-based), `band: Band`
- `enum KeyNavigator`:
  - `static func start(windowFrame: CGRect?, displays: [DisplayContext]) -> NavState?`: the window's display and the column at its centre, `.full`; falls back to display 0 and column 0.
  - `static func reduce(_ s: NavState, _ key: NavKey, displays: [DisplayContext]) -> NavState`
    - `columnsPlus`, `columnsMinus` and `apply` return `s` re-clamped to the current column count.
    - `nextDisplay` and `previousDisplay` keep the column ratio and wrap.
  - `static func selection(_ s: NavState, displays: [DisplayContext]) -> Selection`
- `struct CycleTracker: Sendable`:
  - `init(timeout: TimeInterval = 2)`
  - `mutating func step(cycle: String, windowKey: String, stepCount: Int, now: Date) -> Int`
- `struct HotkeyTable: Sendable`:
  - `init(_ bindings: [HotkeyBinding])`
  - `func match(keyCode: UInt16, modifiers: Modifiers) -> Command?`: enabled bindings only, exact modifiers.
  - `static func conflicts(_ bindings: [HotkeyBinding], chord: TriggerChord, systemHotkeys: Set<Hotkey>) -> [String: String]`: binding id → human message.
- **TriggerMachine:**
  - `init(chord: TriggerChord, hotkeys: [HotkeyBinding] = [], ringKeyNavigation: Bool = true)`
  - `InputEvent.keyDown` gains `modifiers: Modifiers`, so the case becomes `.keyDown(keyCode:modifiers:location:)`. Update the existing tests.
  - **Ring open:** nav keys produce `.nav(…)` and are suppressed. The mapping:

    | Key (keyCode) | Output |
    |---|---|
    | ← (123), → (124) | `left` / `right`, or `extendLeft` / `extendRight` with Shift |
    | ↑ (126), ↓ (125) | `bandUp` / `bandDown` |
    | 1–9 | `column(n)` |
    | `=` (24), `-` (27) | `columnsPlus` / `columnsMinus` |
    | Tab (48) | `nextDisplay`, or `previousDisplay` with Shift |
    | Return (36), keypad Enter (76) | `.nav(.apply)` and close |

    Esc behaves as in M1. Any other key: if it matches a hotkey, output `[.cancel, .command(c)]` and suppress; otherwise `.cancel` and pass through.
  - **Ring closed:** a key matching a hotkey outputs `.command(c)` and is suppressed. Everything else is ignored.
  - With `ringKeyNavigation == false`, keys behave as in M1.
- **Settings:**
  - `SettingsValidation.currentSchemaVersion = 2`
  - `TesseraSettings.schemaVersion` defaults to 2
  - `enum SettingsMigration { static func migrate(_ data: Data) throws -> (data: Data, migratedFrom: Int?) }`: v1 JSON gets the new keys with their default values and `schemaVersion: 2`.
  - `SettingsStore.load()`:
    1. Read the file.
    2. Run `migrate`.
    3. If a migration happened, write `settings.v1-backup.json` (never overwriting an existing one), then save v2.
    4. Decode.
  - Update tests that used schema 2 as "newer" to use 3.

- [x] For each unit: write the tests (including Review Focus 3, 4 and 5), watch them fail, implement, watch them pass, then commit with a `feat(keyboard): …` message.

---

### Track I: CommandExecutor and Coordinator (app; agent "executor")

**Files:**
- `Tessera/App/CommandExecutor.swift`
- edits to `Tessera/App/Coordinator.swift`, `Tessera/App/AppDelegate.swift` and `Tessera/Services/InputService.swift`

**Produces:**
- `@MainActor final class CommandExecutor: CommandExecuting`
  - `init(model:displays:windows:presenter:store:)`, built from Coordinator-owned services. Move the `WindowService` and `SettingsStore` instances so both share one, for example by making them Coordinator `let`s passed in.
  - **apply:** the frontmost window → resolve the display (G) → `TargetResolver.frame` → `WindowService.apply`.
  - **cycle:** `CycleTracker.step`, skipping steps whose frame is within 1 pt of the current frame.
  - **columns:** write a settings override.
  - **moveToDisplay:** find the window's current span on its display (the nearest columns to its frame), relocate it, apply. For a non-grid frame, scale it proportionally.
  - **Other commands:** undo, `openSettings` (presenter), `listDisplays` / `describeWindow`, and export/import through the store.
- Sets `CommandBridge.executor` at launch.
- **Coordinator:**
  - Handles `.nav`: keyboard selection via KeyNavigator, which overrides the cursor until the mouse moves at least 10 pt. `columnsPlus` and `columnsMinus` reuse `step(±1)`. `.nav(.apply)` applies.
  - Handles `.command` with `CommandBridge.execute`. A failure shows a HUD with the message.
  - Posts a VoiceOver announcement (`NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.high.rawValue])`) when `announceSelection` is on.
- **InputService:**
  - Add `updateHotkeys(_ bindings: [HotkeyBinding], ringKeyNavigation: Bool)`.
  - Rebuild the machine when it is closed.
  - Pass `Modifiers(deviceKeyCodes:)` on keyDown.
- **URL handling:** in `AppDelegate.application(_:open:)`, parse with `CommandParser.parse(url:)` and run with `CommandBridge.execute`. Show a HUD on errors.
- Until G and H merge, stub their signatures in `Tessera/_Stubs/TrackGHStubs.swift`, with the header comment `// TEMPORARY STUB — coordinator deletes at merge`.
- [x] Build passes → commit `feat(app): command executor and keyboard ring`.

---

### Track J: CLI, socket server, AppleScript (app plus a package executable; agent "automation")

**Files:**
- `Packages/TesseraCore/Sources/TesseraCLI/main.swift`, plus the executable target `tessera` in `Package.swift`. You may edit `Package.swift` for this target only.
- `Tessera/Automation/SocketServer.swift`
- `Tessera/Automation/CLIInstaller.swift`
- `Tessera/Tessera.sdef`
- `Tessera/Automation/ScriptCommands.swift`
- project.yml: you may add the build phase that embeds the CLI at `Contents/MacOS/tessera`. Nothing else.

**Socket server** (`@MainActor final class SocketServer`):
- `func start()`: creates `~/Library/Application Support/Tessera/tessera.sock`. Remove a stale file first, and `chmod 0600`.
- `func stop()`.
- Accepts connections off the main thread. Each connection is one request line, decoded as `Command` JSON, run with `await CommandBridge.execute`, and answered with one `CommandResult` JSON line.
- Use a POSIX `socket` / `bind` / `listen` / `accept` on a dedicated thread, or `Network.framework` `NWListener` with a Unix endpoint.

**CLI:**
- Parse argv with `CommandParser.parse(arguments:)`, connect to the socket, send, and print the result.
- Output is human-readable by default, or JSON with `--json`.
- Exit codes: 0 ok, 1 command error, 2 usage error, 3 app not running.

**CLIInstaller:**
- `@MainActor enum CLIInstaller { static func install() -> Result<URL, Error> }`
- Symlinks `Bundle.main/Contents/MacOS/tessera` to `~/.local/bin/tessera`, creating the folder if needed.
- `static var isInstalled: Bool`.

**AppleScript:**
- `Tessera.sdef` with the M2 spec §5 commands.
- One `NSScriptCommand` subclass per command. Each builds a `Command` and runs it with `CommandBridge.execute`. Bridging async to the script engine: `suspendExecution()` / `resumeExecution(withResult:)`.
- `list displays` returns a list of records.

Until G merges, stub its signatures in `Tessera/_Stubs/TrackGStubs.swift`, and in the CLI target if needed.

The AppDelegate wiring for `SocketServer().start()` is done by the coordinator at merge. Tell the coordinator the exact call.

- [ ] Build passes. Then `swift build --product tessera` passes. → commit `feat(automation): CLI, socket server, AppleScript`.

---

### Track K: App Intents, Shortcuts pane, keyboard pass (app; agent "keyboard-ui")

**Files:**
- `Tessera/Intents/*.swift`
- `Tessera/UI/ShortcutsPane.swift`
- `Tessera/UI/HotkeyRecorder.swift`
- `Tessera/UI/CyclesEditor.swift`
- edits to the existing `Tessera/UI/*` files for the keyboard pass

**App Intents:**
- One `AppIntent` per command in M2 spec §5, each calling `CommandBridge.execute` and returning a result or dialog.
- `DisplayEntity` (`AppEntity`) with an `EntityQuery` backed by `.listDisplays`.
- `WindowActionAppEnum` for actions.
- `TesseraShortcuts: AppShortcutsProvider` with phrases that include `\(.applicationName)`.

**Shortcuts pane** (spec §6):
- **Bindings list:** the recorder, a command picker covering every Command type with parameters, an enabled toggle, and a conflict badge from `HotkeyTable.conflicts`. Get system hotkeys with `CopySymbolicHotKeys`; add a helper in `Tessera/UI/SystemHotkeys.swift`.
- Add, remove, and restore defaults.
- **Cycles editor:** reorder with ⌘↑ / ⌘↓.
- **Install CLI** button in General, calling `CLIInstaller` (stubbed until J merges).
- **Ring keyboard section:** `ringKeyNavigation` and `announceSelection` toggles, plus a table of the ring keys.

**Keyboard pass:**
- ⌘1–8 switches panes.
- Every control is focusable in a logical order.
- Recorders: Space or Return starts recording, Esc cancels, Delete clears.
- Onboarding: Return continues, Esc skips.
- Add "Shortcuts…" to the menu bar menu (`TesseraApp.swift` is coordinator-owned; tell the coordinator the exact item).

Until G, H and J merge, stub their signatures in `Tessera/_Stubs/TrackGHJStubs.swift`.

- [ ] Build passes → commit `feat(ui): App Intents, Shortcuts pane, keyboard pass`.

---

### Track L: Integration (coordinator)
- [ ] Merge G and H, then I, J and K. Delete every `_Stubs` file. Wire the SocketServer start/stop and the menu item.
- [ ] Run `swift test`. Build the app and `swift build --product tessera`. Smoke tests:
  - launch the app
  - `tessera displays --json` against the running app; it may fail without a window session. Exit code 0 or 1 is fine; 3 is not.
- [ ] Reviewer pass on the keyboard and automation paths. Fix what it confirms.
- [ ] Update the README with the keyboard and automation sections.
- [ ] Hand off the manual checks from M2 spec §8.
