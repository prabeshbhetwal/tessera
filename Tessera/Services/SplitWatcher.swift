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
    var onReflowBegan: (() -> Void)?
    var onReflowEnded: (() -> Void)?
    var onHandBegan: (() -> Void)?
    var onManualDeparture: (() -> Void)?
    /// A watched window closed or was minimised (see `closed`): the group as it last settled, its display's storage
    /// key, and whether a minimise rather than a close ended the watch.
    var onWindowClosed: ((_ group: [(window: WindowRef, frame: CGRect)], _ displayKey: String, _ minimised: Bool, _ baselineAt: ContinuousClock.Instant) -> Void)?

    private static let notifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                                        kAXWindowMiniaturizedNotification]
    private static let timeout: Float = 0.3

    let windows: WindowService
    let displays: DisplayService
    let model: SettingsModel
    /// One observer per app, with the window elements registered on it.
    private var observers: [(observer: AXObserver, elements: [AXUIElement])] = []
    private(set) var key: SplitKey?
    /// The windows themselves: another Space can hold the same apps (the same `key`) in different windows.
    private(set) var watched: [WindowRef] = []
    /// False for Tile Evenly: neighbours still follow a hand adjustment, but the arrangement is never saved.
    var learns = true
    /// Tessera moves in flight, and when the notifications of the last one to end stop counting as Tessera's.
    private var ownMoves = 0
    private var ignoreUntil: ContinuousClock.Instant = .now
    var pending: Task<Void, Never>?
    /// Bumped by every `stop()`, so a debounce or learn begun under an earlier watch never writes.
    var generation = 0
    var watchContext: WindowMutationContext.Ticket?
    var revision: Int { generation }
    var settledGroup: (group: ManagedWindowGroup, at: ContinuousClock.Instant) { (baseline, baselineAt) }
    /// The group as it last settled, to tell which window the person changed (see `reflow`).
    var baseline: [(window: WindowRef, frame: CGRect)] = [] {
        didSet { baselineAt = .now }
    }
    private var baselineAt: ContinuousClock.Instant = .now
    /// A hand adjustment is waiting for its debounce; a baseline read now would absorb it.
    var adjusting = false
    /// A mouse button was down while the adjustment waiting to be learned happened. Without it the change was an app
    /// resizing its own window or macOS moving windows (display wake, a Space switch): neighbours may still follow, but
    /// the arrangement is not saved, so a window that opened floating in a hole never becomes part of a split.
    var byHand = false

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
        baseline = group  // close/minimise can arrive before the delayed read-back
        watchContext = WindowMutationScope.ticket ?? windows.mutationContext.capture()

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
        baseline = group  // the frames now, so a window closed before the refresh below lands leaves its tiled gap to fill
        refreshBaseline()  // the frames Tile just set
    }

    /// Re-reads the group once Tessera's moves have settled, so the next hand adjustment is compared with where the
    /// windows are now. Skipped while a hand adjustment waits to be learned: that pass compares with the old baseline.
    func refreshBaseline() {
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
        cancelAdjustment()
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
        watchContext = nil
        watched = []
        baseline = []
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

    func handle(_ notification: String, element: AXUIElement) {
        // A queued callback from an earlier group must not close or adjust its replacement.
        guard key != nil, watched.contains(where: { CFEqual($0.element, element) }) else { return }
        switch notification {
        case kAXUIElementDestroyedNotification:
            closed()
        case kAXWindowMiniaturizedNotification:
            // Leaving the space empty: nothing moves, and the watch ends at its next check, as before.
            if model.settings.minimiseFillsGap { closed(minimised: true) }
        default:
            if quiet {
                adjusting = true
                if NSEvent.pressedMouseButtons != 0, !byHand { byHand = true; onHandBegan?() }
                schedule()
            }
        }
    }

    /// A watched window closed or was `minimised`, or its app quit: the watch ends, and `onWindowClosed` gets the group
    /// as it last settled.
    func closed(minimised: Bool = false) {
        if minimised, !model.settings.minimiseFillsGap {
            stop()
            onEnded?()
            return
        }
        guard let display = key?.display else { return }
        let group = baseline
        let observedAt = baselineAt
        stop()
        onWindowClosed?(group, display, minimised, observedAt)
    }

    /// A hand adjustment waits to be handled, or a move (Tessera's or this watcher's reflow) is settling: re-arming now
    /// would drop it.
    var isBusy: Bool { adjusting || !quiet }

    /// No Tessera move is in flight or still settling.
    private var quiet: Bool { ownMoves == 0 && ContinuousClock.now >= ignoreUntil }

    /// (Re)starts the debounce; the learn runs when it ends.
    private func schedule() {
        pending?.cancel()
        let generation = self.generation
        let ticket = watchContext
        pending = Task { [weak self] in
            await WindowMutationScope.$ticket.withValue(ticket) {
                do { try await Task.sleep(for: Self.debounce) } catch { return }
                await self?.learnNow(generation)
            }
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
            var removed: [Bool] = []
            for window in watched {
                if let kind = await windows.removalKind(of: window) { removed.append(kind) }
            }
            guard generation == self.generation, !Task.isCancelled else { return }
            if !removed.isEmpty { closed(minimised: removed.allSatisfy { $0 }) }
            else {
                if byHand, let ticket = watchContext,
                   windows.mutationContext.isCurrent(ticket, on: [key.display], refreshSpaces: true) {
                    onManualDeparture?()
                    stop()
                }
                onEnded?()
            }
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
        let handMade = byHand
        byHand = false
        guard learns, handMade else { return }
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
}

/// AX calls this on the main run loop, where `watch` adds every observer's source; `refcon` is the watcher.
private func splitWatcherCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<SplitWatcher>.fromOpaque(refcon)
    let name = notification as String
    nonisolated(unsafe) let element = element
    MainActor.assumeIsolated {
        watcher.takeUnretainedValue().handle(name, element: element)
    }
}
