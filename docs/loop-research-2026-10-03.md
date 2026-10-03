# Loop fork: research and improvement plan

Date: 2026-10-03
Upstream: https://github.com/MrKai77/Loop at `61e9b09` (2026-09-30)
Local clone: `loop/`
Goal: build an independent fork. Loop is GPL-3.0, so the fork must stay GPL-3.0 and open source.

---

## 1. Snapshot

| Metric | Value |
|---|---|
| Stars / forks | 11,708 / 276 |
| Contributors | 29 |
| Open issues / PRs | 53 / 5 |
| Issues closed as "not planned" | 124 (mostly inactivity) |
| Code | 179 Swift files, 31,838 lines |
| Tests | 40 tests, 1,290 lines; none run in CI |
| Min macOS | 13.0 |
| Last stable release | 1.4.2 (2026-01-26); no stable release for 8 months, most work ships in the rolling `prerelease` build |
| Dependencies | Defaults, ZIPFoundation (version-pinned); Scribe, Luminare, Subsurface (track `branch = main`) |

Loop is a mouse-first macOS window manager: hold a trigger key, move the cursor, and a radial menu shows a live preview of where the window will go. It also has keybinds, drag-snapping, stash, action cycles, trackpad gestures (prerelease), moving windows across Spaces (prerelease) and a `loop://` URL scheme.

---

## 2. Fork setup blockers (do these first)

These are verified in the code. Without them, a fork build breaks itself or breaks a real Loop install.

1. **The updater targets upstream.** `Loop/Updater/UpdaterModels.swift:32-33` fetches from `api.github.com/repos/MrKai77/Loop/releases`. A fork build would download upstream Loop and replace itself. Point it at your fork's releases or turn auto-update off.
2. **The bundle IDs collide.** `com.MrKai77.Loop`, `.DockTile` and `LoopTests` are in `project.pbxproj:468-640`. On launch, `AppDelegate.swift:63-79` broadcasts a terminate message to older copies, so a fork with the same ID will quit a real Loop install. Change every bundle ID.
3. **Team ID and signing.** `DEVELOPMENT_TEAM = 5F967GYF84` is Loop's team. The privileged helper also pins that team in `Shared/PrivilegedInstallerProtocol.swift:33`. Replace both with your own team.
4. **Branding.** Rename the app and replace the icon. GPL covers the code, not the "Loop" name or artwork. Update the hard-coded GitHub links in `AboutConfiguration.swift:42,295` and `ChangelogSectionView.swift:104`.
5. **Reproducible builds.** `.gitignore:14` excludes `project.xcworkspace`, so `Package.resolved` is never committed while three packages follow `main`. Commit the lockfile and pin those three packages to revisions.

Estimate: about 3 hours.

---

## 3. Verified defects

| # | Issue | Location | Fix | Effort |
|---|---|---|---|---|
| D1 | **Single-action radial menu drops the selection.** When only one action is configured, `newAction = radialMenuActions.first` runs and then `return` exits before `changeAction` is called. | `MouseInteractionObserver.swift:142-144` | Fall through instead of returning. | 0.5 h |
| D2 | **Root helper accepts any validly signed bundle.** `SecStaticCodeCheckValidity(..., nil)` has no requirement, so an ad-hoc or other-team signature passes. The SHA-256 comes from the same GitHub response as the zip, so it adds no independent trust. | `LoopUpdaterHelper/PrivilegedInstaller.swift:268`, `Loop/Updater/UpdateInstaller.swift:446` | Pass a `SecRequirement`: `anchor apple generic and certificate leaf[subject.OU] = "<TEAM>" and identifier "<bundle id>"`. | 1-2 h |
| D3 | **Data races between the event-tap thread and main.** Affects `effectiveEventFlags`, `canPassthroughNextSpecialEvent`, `BaseEventTapMonitor` restart state, and `WindowDragManager` reading main-actor state from the tap thread. | `KeybindTrigger.swift:100,109`, `LoopManager.swift:133,665`, `BaseEventTapMonitor.swift:95-118`, `WindowDragManager.swift:70-98` | Use one main-actor hop or locks, then turn on `SWIFT_STRICT_CONCURRENCY=complete`. | 8-16 h |
| D4 | **A hung app can freeze Loop for about 6 s.** The AX messaging timeout is set only for the Dock. | `Utilities/MissionControl.swift:21` | Call `AXUIElementSetMessagingTimeout` (0.25-0.5 s) on every app element. | 2 h |
| D5 | **Crash-prone force casts.** | `WallpaperImageFetcher.swift:63`, `SkyLightSymbolLoader.swift:116` (non-optional return from a private API), `Window.swift:410` and `WindowDragManager.swift:33` (`NSScreen.screens[0]`), `AXUIElement+Extensions.swift:77-83` | Use guards and optionals. | 2 h |
| D6 | **Two private symbols are linked with `@_silgen_name`.** A missing symbol crashes at load instead of degrading. | `PrivateApis.swift:21,27` | Move them to the existing `dlsym` loader. | 1 h |
| D7 | **The lint workflow path filter is wrong.** It watches `swiftformat.yml` and `.swiftformat.yml`, but the files are `lint.yml` and `.swiftformat`. | `.github/workflows/lint.yml:7-8` | Fix the paths. | 0.1 h |

Open upstream bugs worth fixing in the fork:
- #1164 Loop quits when the settings window closes.
- #1145 Scroll locks after a trigger.
- #1148 Stale constraints when maximizing across displays.
- #1139 Media keys trigger Loop.
- #1058 The URL scheme shows a Dock icon.

---

## 4. Performance hot paths

All of these are verified.

| Hot path | Problem | Fix |
|---|---|---|
| Every mouse move while the menu is open (`MouseInteractionObserver.swift:121`) | A new `Task` per event, and `Defaults[.radialMenuActions]` is decoded up to 3 times. | Cache the decoded values and refresh them through Defaults observation. |
| Every drag event (`WindowDragManager.swift:102-130`) | A new `Task`, several AX `frame` reads, and a Codable decode of the stash map. | Coalesce to one per frame and cache the stash map. |
| Every animation frame (`WindowTransformAnimation.swift:67,118-197`) | Synchronous AX set/get, plus 2 extra `frame` reads per frame. The easing is applied twice. | Drop the reads and use one easing. |
| Every key event (`KeybindTrigger.swift:37-39,176`) | Defaults reads. | Cache. |

Estimate: about 8-10 hours for all four.

---

## 5. What users want

### Top open requests (by reactions and comments)
1. Resize adjacent windows together (#264, 11 reactions). The maintainer is working on it slowly.
2. A generic keyboard shortcut that opens the radial menu (#260).
3. Windows-style Snap Assist (#215).
4. Import/export all settings (#945). Planned upstream.
5. Auto-tile / "quick tile all" (#243).
6. Custom sizes in the radial menu (#157), plus radial UI customization (#1155) and an adjustable deadzone (#1154).
7. More trigger inputs: Caps Lock, F13-F24, any mouse button, Logitech buttons (#712, #701, #100, #1106, #1140).
8. Saved layouts and per-app default frames (#144, #988, #76).
9. Pin window always-on-top (#1121).

### Rejected upstream (open for the fork)
- Grids and thirds grids (#579, #580, #550): "not Loop's core model".
- Sixths (#986).
- Raycast integration (#756): the core team won't build it.

### In flight upstream (do not duplicate; cherry-pick when merged)
- #1156 Screen order.
- #1141 Radial menu across displays.
- #1133 Cursor stutter.
- #1117 Cached base frame.
- #1076 New URL API and CLI.

---

## 6. Competitive position

| | Loop | Rectangle Pro | Moom 4 | Raycast | AeroSpace | macOS Tahoe |
|---|---|---|---|---|---|---|
| Radial / gesture UI | **Y** | cursor/throw | hover grid | N | N | N |
| Saved layouts, auto-restored on display change | **N** | Y | Y | Pro | workspaces | N |
| Adjacent-window resize | **N** | Y | ? | N | Y (tree) | N |
| Grids | partial | Y | Y | Pro | N | halves/quarters |
| Per-app rules | partial | Y | ? | N | Y | N |
| Price / OSS | Free / Y | $9.99 / N | $15 / N | Free+Pro / N | Free / Y | built in |

- **Loop's moat:** the mouse-first radial menu with live preview, theming, and paid-tier features (stash, cycles, cursor resize) for free.
- **Biggest gap:** saved layouts that restore automatically, including when a display is plugged in or out. This is the top theme on r/macapps.

---

## 7. Fork roadmap

### Phase 0: Make the fork safe to run (about 3 h)
- Do section 2 items 1-5.
- Fix D7.
- Add `xcodebuild test` to CI.

### Phase 1: Stability and security (about 15-25 h)
- D1, D2, D4, D5, D6, then D3.
- Hot-path caching from section 4.
- Tests for `WindowFrameResolver` (start with the pure overload at line 100), `Migrator` (risk of losing settings) and the updater's version and checksum logic.

### Phase 2: Quick wins users ask for (about 15-20 h)
- Settings import/export (#945).
- Pin always-on-top (#1121), using the SkyLight window-level calls that already exist in `SkyLightToolBelt`.
- Extra trigger inputs: F13-F24, Caps Lock, mouse buttons.
- Adjustable deadzone (#1154).
- Accessibility labels and Reduce Motion support. The app currently has zero accessibility modifiers.

### Phase 3: Differentiators that fit the radial menu
1. **Layout Ring.** A modifier or scroll while holding the trigger swaps the wedges for saved multi-window layouts. When a display connects, offer the matching layout. Closes the biggest competitive gap.
2. **Dwell-to-expand sub-rings.** Hovering on a wedge reveals thirds, two-thirds and custom sizes. This gives grid precision without a grid UI (#157, #592; upstream rejected grids).
3. **Linked-edge resize.** Holding the trigger and scrolling over a shared edge resizes both neighbouring windows (#264).
4. **Companion picker.** After a snap, show a mini ring of recent windows to fill the empty half, like Snap Assist (#215).
5. **Outer-ring throw.** Dragging past the ring shows previews of Spaces and displays as drop targets.
6. **Context-aware radial.** Wedge sets change with the frontmost app, which doubles as per-app rules (#76).

### Keeping the fork in sync with upstream
- Add `upstream` as a git remote.
- Rebase or merge weekly, because upstream is active (62 commits since March).
- Keep fork changes in separate files or extensions where possible. `LoopManager`, `WindowEngine` and `MouseInteractionObserver` are the most-changed upstream files and will produce merge conflicts.

---

## Sources
- Code audit of `loop/` at `61e9b09`. Every file:line above was read directly.
- GitHub REST API: issues, PRs, releases and labels for MrKai77/Loop.
- r/macapps threads: [1](https://www.reddit.com/r/macapps/comments/1mdginb/mac_window_management_tool_for_standalone_and/), [2](https://www.reddit.com/r/macapps/comments/1h2uu5v/best_window_manager_app/), [3](https://www.reddit.com/r/macapps/comments/1oa1n1n/rectangle_raycast_or_wins_window_manager_for_most/).
- HN launch thread: https://news.ycombinator.com/item?id=40717698
- Many Tricks blog (Moom 4): https://manytricks.com/blog/?p=6385
- Apple: window tiling shortcuts: https://support.apple.com/guide/mac-help/mac-window-tiling-icons-keyboard-shortcuts-mchl9674d0b0/mac
- Rectangle comparison: https://rectangleapp.com/comparison
