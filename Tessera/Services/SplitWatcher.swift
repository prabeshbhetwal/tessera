import AppKit
import ApplicationServices
import TesseraCore

/// Watches one display's tiled windows (see `SplitWatchers`) for hand adjustments. About a second after the person stops
/// moving or resizing them, it re-reads the display; when one window changed, the windows beside it follow its new
/// edges (`splitReflowsNeighbours`), and the arrangement is then remembered as a learned split. Tessera's own moves are
/// ignored (see `beginOwnMove`); they never end the watch.
///
/// Observers hold `self` unretained (see `watch`). That is safe because the watcher lives for the app's lifetime
/// (SplitWatchers keeps one per display) and `stop()` removes every registration before a new watch begins.
@MainActor
final class SplitWatcher {
    /// Quiet time after the last move or resize before the arrangement is learned.
    static let debounce: Duration = .seconds(1)
    /// How long a Tessera move's own notifications keep arriving after the move returns.
    static let settle: Duration = .milliseconds(300)

    var onLearned: ((String) -> Void)?
    var onHelpEvent: ((HelpEvent) -> Void)?
    /// The watched group changed (a window joined or left) and the watch ended; `SplitWatchers` re-arms.
    var onEnded: (() -> Void)?
    /// A watched window closed or was minimised (see `closed`): the group as it last settled, its display's storage
    /// key, and the window when it was minimised rather than closed.
    var onWindowClosed: ((_ group: [(window: WindowRef, frame: CGRect)], _ displayKey: String, _ minimised: WindowRef?)
        -> Void)?

    private static let notifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                                        kAXWindowMiniaturizedNotification]
    private static let timeout: Float = 0.3

    private let windows: WindowService
    private let displays: DisplayService
    let model: SettingsModel
    /// One observer per app, with the window elements registered on it.
    private var observers: [(observer: AXObserver, elements: [AXUIElement])] = []
    private(set) var key: SplitKey?
    /// The windows themselves: another Space can hold the same apps (the same `key`) in different windows.
    private(set) var watched: [WindowRef] = []
    /// False for Tile Evenly: neighbours still follow a hand adjustment, but the arrangement is never saved.
    private var learns = true
    /// Tessera moves in flight, and when the notifications of the last one to end stop counting as Tessera's.
    private var ownMoves = 0
    private var ignoreUntil: ContinuousClock.Instant = .now
    private var pending: Task<Void, Never>?
    /// Bumped by every `stop()`, so a debounce or learn begun under an earlier watch never writes.
    private var generation = 0
    /// The group as it last settled, to tell which window the person changed (see `reflow`).
    private var baseline: [(window: WindowRef, frame: CGRect)] = []
    /// A hand adjustment is waiting for its debounce; a baseline read now would absorb it.
    private var adjusting = false

    init(windows: WindowService, displays: DisplayService, model: SettingsModel) {
        self.windows = windows
        self.displays = displays
        self.model = model
    }

    /// Starts watching `group`, the windows on `display`. Replaces any earlier watch.
    func watch(_ group: [(window: WindowRef, frame: CGRect)], display: DisplayContext, learns: Bool = true) {
        stop()
        guard model.settings.learnSplits else { return }
        key = SplitKey(group, on: display)
        self.learns = learns
        watched = group.map(\.window)

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
        refreshBaseline()  // the frames Tile just set
    }

    /// Re-reads the group once Tessera's moves have settled, so the next hand adjustment is compared with where the
    /// windows are now. Skipped while a hand adjustment waits to be learned: that pass compares with the old baseline.
    private func refreshBaseline() {
        guard key != nil else { return }
        let generation = self.generation
        Task { [weak self] in
            repeat {
                do { try await Task.sleep(for: Self.settle) } catch { return }
            } while self?.quiet == false
            guard let self, generation == self.generation, !self.adjusting else { return }
            let group = await self.currentGroup()
            guard generation == self.generation, !self.adjusting, self.quiet, let group else { return }
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
        watched = []
        baseline = []
        adjusting = false
    }

    /// Brackets each of Tessera's own moves (`CommandExecutor.place`; balance every begin with an end). Moves and
    /// resizes while any is in flight, and for `settle` after the last one ends, are Tessera's and are ignored; the
    /// baseline is then re-read, so a command's move never counts as the person's.
    func beginOwnMove() {
        ownMoves += 1
    }

    func endOwnMove() {
        ownMoves -= 1
        guard ownMoves == 0 else { return }
        ignoreUntil = .now + Self.settle
        refreshBaseline()
    }

    fileprivate func handle(_ notification: String, element: AXUIElement) {
        guard key != nil else { return }  // queued before stop()
        switch notification {
        case kAXUIElementDestroyedNotification:
            closed()
        case kAXWindowMiniaturizedNotification:
            minimised(element)
        default:
            if quiet {
                adjusting = true
                schedule()
            }
        }
    }

    /// A watched window closed or was `minimised`, or its app quit: the watch ends, and `onWindowClosed` gets the group
    /// as it last settled.
    func closed(minimised: WindowRef? = nil) {
        guard let display = key?.display else { return }
        let group = baseline
        stop()
        onWindowClosed?(group, display, minimised)
    }

    /// Watching a window of the app with this process ID.
    func watches(pid: pid_t) -> Bool { watched.contains { $0.pid == pid } }

    /// A hand adjustment waits to be handled, or a move (Tessera's or this watcher's reflow) is settling: re-arming now
    /// would drop it.
    var isBusy: Bool { adjusting || !quiet }

    /// Watching exactly these windows.
    func watches(_ group: [(window: WindowRef, frame: CGRect)]) -> Bool {
        group.count == watched.count && group.allSatisfy { entry in watched.contains(entry.window) }
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
        adjusting = false  // this pass handles it
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
            onEnded?()
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
        guard learns else { return }
        let previous = SplitMemory.lookup(key, in: model.settings.learnedSplits)
        switch save(visible, display: display, onlyIfChanged: true) {
        case .failure(let rejection):
            onHelpEvent?(.make(kind: .splitNotLearned(reason: rejection.message), source: .hand, display: display,
                               group: onScreenOrder(visible, portrait: display.range.isPortrait),
                               split: nil, previous: nil))
        case .success((_, false)):
            return
        case .success((_, true)):
            let split = SplitMemory.lookup(key, in: model.settings.learnedSplits)
            onLearned?("Learned split · \(SplitLabel.apps(key)) · \(SplitLabel.display(key, displays: [display]))")
            onHelpEvent?(.make(kind: .splitLearned, source: .hand, display: display,
                               group: onScreenOrder(visible, portrait: display.range.isPortrait), split: split,
                               previous: previous))
        }
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
    /// edges (`SplitReflow`) as one undo step, and makes where they landed the baseline: the next pass then sees no
    /// change (so it learns, even if an app refused its size) unless the person adjusts again. True when it moved them,
    /// or when a mouse button is still down (a drag held still); either way the caller tries again later.
    private func reflow(_ visible: [(window: WindowRef, frame: CGRect)], display: DisplayContext) async -> Bool {
        let before = visible.compactMap { entry in baseline.first { $0.window == entry.window }?.frame }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        guard model.settings.splitReflowsNeighbours, baseline.count == visible.count, before.count == visible.count,
              let goals = SplitReflow.frames(before: before, after: visible.map(\.frame), usable: usable,
                                             gap: display.profile.gap) else { return false }
        // Mid-drag: following an edge that is still moving would leave the neighbours behind the final one.
        guard NSEvent.pressedMouseButtons == 0 else { return true }
        let moves = visible.indices.filter { visible[$0].frame != goals[$0] }.map { (index: $0, window: visible[$0].window) }
        let generation = self.generation
        beginOwnMove()
        defer { endOwnMove() }
        let (results, undoMarker) = await windows.moveTogether(  // one ⌃⌥Z puts the neighbours back
            moves.map { (window: $0.window, goal: goals[$0.index]) }, primaryHeight: DisplayService.primaryHeight,
            duration: model.glideSeconds)
        var landed: [Int: CGRect] = [:]
        for (move, frame) in zip(moves, results) { landed[move.index] = frame }
        if generation == self.generation {
            let finals = visible.indices.map { (window: visible[$0].window, frame: landed[$0] ?? visible[$0].frame) }
            baseline = finals
            let moved = Set(moves.map(\.index))
            let changedIndex = visible.indices.first {
                !moved.contains($0) && !CommandExecutor.sameFrame(visible[$0].frame, before[$0])
            }
            let followed = moves.filter { landed[$0.index] != nil }  // a follower whose app refused didn't follow
            if !followed.isEmpty, let changedIndex {
                let kind = HelpEventKind.neighboursFollowed(
                    changed: HelpEvent.appName(visible[changedIndex].window),
                    followers: followed.map { HelpEvent.appName($0.window) })
                onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                                   group: onScreenOrder(finals, portrait: display.range.isPortrait),
                                   split: nil, previous: nil, undoMarker: undoMarker))
            }
        }
        return true
    }
}

/// AX calls this on the main run loop, where `watch` adds every observer's source; `refcon` is the watcher.
private func splitWatcherCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<SplitWatcher>.fromOpaque(refcon)
    let name = notification as String
    nonisolated(unsafe) let element = element  // never leaves the main thread this callback runs on
    MainActor.assumeIsolated {
        watcher.takeUnretainedValue().handle(name, element: element)
    }
}
