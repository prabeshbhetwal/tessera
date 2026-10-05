import AppKit
import ApplicationServices
import TesseraCore

/// After a Tile or Remember, watches the group's windows for hand adjustments. About a second after the person stops
/// moving or resizing them, it re-reads the display and remembers the arrangement as a learned split. Tessera's own
/// moves are ignored (see `beginOwnMove`); they never end the watch.
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
        // The display as it is now, so a gap or padding edited since the watch began counts; gone ends the watch.
        guard model.settings.learnSplits,
              let display = displays.displays.first(where: { $0.id.storageKey == key.display }) else {
            stop()
            return
        }
        // Tessera is moving windows: try again once they settle, so a glide is never read half-way.
        guard quiet else {
            schedule()
            return
        }
        let visible = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                   excluding: Set(model.settings.excludedBundleIDs))
        // A newer move (which cancels this task), a stop or a new watch while reading: the newer state wins.
        guard generation == self.generation, !Task.isCancelled else { return }
        guard quiet else {
            schedule()
            return
        }
        // A window joined, left or moved to another display: this is no longer the arrangement that was tiled.
        guard SplitKey(visible, on: display) == key else {
            stop()
            return
        }
        // An arrangement that can't be learned (say, windows overlapping) is skipped, and so is one that only repeats
        // the stored split (a slow app's late notification); the next adjustment tries again.
        guard case .success((_, true)) = save(visible, display: display, onlyIfChanged: true) else { return }
        onLearned?("Learned split · \(SplitLabel.apps(key)) · \(SplitLabel.display(key, displays: [display]))")
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
