import AppKit
import ApplicationServices
import TesseraCore

/// After a Tile or Remember, watches the group's windows for hand adjustments. About a second after the person stops
/// moving or resizing them, it re-reads the display; when one window changed, the windows beside it follow its new
/// edges (`splitReflowsNeighbours`), and the arrangement is then remembered as a learned split. Tessera's own moves are
/// ignored (see `beginOwnMove`); they never end the watch.
///
/// Observers hold `self` unretained (see `watch`). That is safe because the watcher lives for the app's lifetime
/// (CommandExecutor owns it) and `stop()` removes every registration before a new watch begins.
@MainActor
final class SplitWatcher {
    /// Quiet time after the last move or resize before the arrangement is learned.
    static let debounce: Duration = .seconds(1)
    /// How long a Tessera move's own notifications keep arriving after the move returns.
    static let settle: Duration = .milliseconds(300)

    var onLearned: ((String) -> Void)?

    private static let notifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification]
    private static let timeout: Float = 0.3

    private let windows: WindowService
    private let displays: DisplayService
    private let model: SettingsModel
    /// One observer per app, with the window elements registered on it.
    private var observers: [(observer: AXObserver, elements: [AXUIElement])] = []
    private var key: SplitKey?
    /// Tessera moves in flight, and when the notifications of the last one to end stop counting as Tessera's.
    private var ownMoves = 0
    private var ignoreUntil: ContinuousClock.Instant = .now
    private var pending: Task<Void, Never>?
    /// Bumped by every `stop()`, so a debounce or learn begun under an earlier watch never writes.
    private var generation = 0
    /// The group as it last settled, to tell which window the person changed (see `reflow`).
    private var baseline: [(window: WindowRef, frame: CGRect)] = []
    /// The last pass moved neighbours; the next one only learns, so a window that refuses its size can't loop.
    private var reflowed = false

    init(windows: WindowService, displays: DisplayService, model: SettingsModel) {
        self.windows = windows
        self.displays = displays
        self.model = model
    }

    /// Starts watching `group`, the windows just tiled or remembered on `display`. Replaces any earlier watch.
    func watch(_ group: [(window: WindowRef, frame: CGRect)], display: DisplayContext) {
        stop()
        guard model.settings.learnSplits else { return }
        key = SplitKey(group, on: display)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (pid, refs) in Dictionary(grouping: group.map(\.window), by: \.pid) {
            var created: AXObserver?
            guard AXObserverCreate(pid, splitWatcherCallback, &created) == .success, let observer = created else { continue }
            let elements = refs.map(\.element)
            for element in elements {
                AXUIElementSetMessagingTimeout(element, Self.timeout)
                for name in Self.notifications {
                    AXObserverAddNotification(observer, element, name as CFString, refcon)
                }
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers.append((observer, elements))
        }
        // The frames Tile just set, read once its moves have settled.
        let generation = self.generation
        Task { [weak self] in
            repeat {
                do { try await Task.sleep(for: Self.settle) } catch { return }
            } while self?.quiet == false
            guard let self else { return }
            let group = await self.currentGroup()
            // A learn that already ran set a newer baseline.
            guard generation == self.generation, self.baseline.isEmpty, let group else { return }
            self.baseline = group.visible
        }
    }

    /// Stops watching: removes every notification and run-loop source and drops any pending learn.
    func stop() {
        generation += 1
        pending?.cancel()
        pending = nil
        for (observer, elements) in observers {
            for element in elements {
                for name in Self.notifications {
                    AXObserverRemoveNotification(observer, element, name as CFString)
                }
            }
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
        }
        observers = []
        key = nil
        baseline = []
        reflowed = false
    }

    /// Brackets each of Tessera's own moves (`CommandExecutor.place`; balance every begin with an end). Moves and
    /// resizes while any is in flight, and for `settle` after the last one ends, are Tessera's and are ignored.
    func beginOwnMove() {
        ownMoves += 1
    }

    func endOwnMove() {
        ownMoves -= 1
        if ownMoves == 0 { ignoreUntil = .now + Self.settle }
    }

    /// Learns how `found` sit on `display` and saves that as the split for these apps there. With `onlyIfChanged`, a
    /// split within a point of the stored one is not written again and comes back with `changed` false.
    func save(_ found: [(window: WindowRef, frame: CGRect)], display: DisplayContext, onlyIfChanged: Bool = false)
        -> Result<(key: SplitKey, changed: Bool), SplitRejection> {
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let frames = found.map { (bundleID: $0.window.bundleID, frame: $0.frame) }
        let learned = SplitLearner.learn(frames, usable: usable, gap: display.profile.gap)
        return learned.map { slots -> (key: SplitKey, changed: Bool) in
            let key = SplitKey(found, on: display)
            if onlyIfChanged, let stored = SplitMemory.lookup(key, in: model.settings.learnedSplits),
               stored.matches(slots, usable: usable) {
                return (key, false)
            }
            let split = LearnedSplit(key: key, slots: slots, updated: Date())
            model.settings.learnedSplits = SplitMemory.upsert(split, into: model.settings.learnedSplits)
            return (key, true)
        }
    }

    fileprivate func handle(_ notification: String) {
        guard key != nil else { return }  // queued before stop()
        if notification == kAXUIElementDestroyedNotification {
            stop()
            return
        }
        if quiet { schedule() }
    }

    /// No Tessera move is in flight or still settling.
    private var quiet: Bool { ownMoves == 0 && ContinuousClock.now >= ignoreUntil }

    /// (Re)starts the debounce; the learn runs when it ends.
    private func schedule() {
        pending?.cancel()
        let generation = self.generation
        pending = Task { [weak self] in
            do { try await Task.sleep(for: Self.debounce) } catch { return }
            await self?.learnNow(generation)
        }
    }

    private func learnNow(_ generation: Int) async {
        guard generation == self.generation, let key else { return }
        guard model.settings.learnSplits else {
            stop()
            return
        }
        // Tessera is moving windows: try again once they settle, so a glide is never read half-way.
        guard quiet else {
            schedule()
            return
        }
        let group = await currentGroup()
        // A newer move (which cancels this task), a stop or a new watch while reading: the newer state wins.
        guard generation == self.generation, !Task.isCancelled else { return }
        guard quiet else {
            schedule()
            return
        }
        // The display is gone, or a window joined, left or moved to another display: this is no longer the
        // arrangement that was tiled.
        guard let group else {
            stop()
            return
        }
        let (display, visible) = group
        if await reflow(visible, display: display) {
            // Learn once the neighbours have settled, from where they actually ended up.
            if generation == self.generation { schedule() }
            return
        }
        baseline = visible
        // An arrangement that can't be learned (say, windows overlapping) is skipped, and so is one that only repeats
        // the stored split (a slow app's late notification); the next adjustment tries again.
        guard case .success((_, true)) = save(visible, display: display, onlyIfChanged: true) else { return }
        onLearned?("Learned split · \(SplitLabel.apps(key)) · \(SplitLabel.display(key, displays: [display]))")
    }

    /// The watched display as it is now (so a gap or padding edited since the watch began counts) and the windows on
    /// it; nil when the display is gone or its windows are no longer the watched group.
    private func currentGroup() async -> (display: DisplayContext, visible: [(window: WindowRef, frame: CGRect)])? {
        guard let key, let display = displays.displays.first(where: { $0.id.storageKey == key.display }) else { return nil }
        let visible = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                   excluding: Set(model.settings.excludedBundleIDs))
        guard SplitKey(visible, on: display) == key else { return nil }
        return (display: display, visible: visible)
    }

    /// When the person has changed exactly one window since `baseline`, moves the windows beside it to follow its new
    /// edges (`SplitReflow`) as one undo step. True when it moved them, or when a mouse button is still down (a drag
    /// held still); either way the caller tries again later rather than learn now.
    private func reflow(_ visible: [(window: WindowRef, frame: CGRect)], display: DisplayContext) async -> Bool {
        guard !reflowed else {
            reflowed = false
            return false
        }
        let before = visible.compactMap { entry in baseline.first { $0.window == entry.window }?.frame }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        guard model.settings.splitReflowsNeighbours, baseline.count == visible.count, before.count == visible.count,
              let goals = SplitReflow.frames(before: before, after: visible.map(\.frame), usable: usable,
                                             gap: display.profile.gap) else { return false }
        // Mid-drag: following an edge that is still moving would leave the neighbours behind the final one.
        guard NSEvent.pressedMouseButtons == 0 else { return true }
        let moves = zip(visible, goals).filter { $0.0.frame != $0.1 }.map { (window: $0.0.window, goal: $0.1) }
        let (windows, generation, primaryHeight) = (self.windows, self.generation, DisplayService.primaryHeight)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : model.settings.snapSeconds
        beginOwnMove()
        defer { endOwnMove() }
        let batch = await windows.newBatch()
        await withDiscardingTaskGroup { group in
            for move in moves {
                group.addTask {
                    _ = await windows.apply(move.goal, to: move.window, primaryHeight: primaryHeight,
                                            crossingDisplays: false, duration: duration, batch: batch)
                }
            }
        }
        await windows.mergeMoves(batch)  // one ⌃⌥Z puts the neighbours back
        if generation == self.generation { reflowed = true }
        return true
    }
}

extension SplitKey {
    /// The key for `group` on `display`, shared by Tile, Remember and the watcher.
    init(_ group: [(window: WindowRef, frame: CGRect)], on display: DisplayContext) {
        self.init(display: display.id.storageKey, bundleIDs: group.map(\.window.bundleID))
    }
}

/// AX calls this on the main run loop, where `watch` adds every observer's source; `refcon` is the watcher.
private func splitWatcherCallback(_: AXObserver, _: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<SplitWatcher>.fromOpaque(refcon)
    let name = notification as String
    MainActor.assumeIsolated {
        watcher.takeUnretainedValue().handle(name)
    }
}
