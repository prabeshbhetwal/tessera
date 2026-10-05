import AppKit
import ApplicationServices
import TesseraCore

/// After a Tile, watches the tiled windows for hand adjustments. About a second after the person stops moving or
/// resizing them, it re-reads the display and remembers the arrangement as a learned split.
///
/// Observers hold `self` unretained (see `watch`). That is safe because the watcher lives for the app's lifetime
/// (CommandExecutor owns it) and `stop()` removes every registration before a new watch begins.
@MainActor
final class SplitWatcher {
    /// Quiet time after the last move or resize before the arrangement is learned.
    static let debounce: Duration = .seconds(1)
    /// How long a Tile's own moves keep arriving; callers pass `.now + settle` as `ignoreUntil`.
    static let settle: Duration = .milliseconds(300)

    var onLearned: ((String) -> Void)?

    private static let notifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification]
    private static let timeout: Float = 0.3

    private let windows: WindowService
    private let model: SettingsModel
    /// One observer per app, with the window elements registered on it.
    private var observers: [(observer: AXObserver, elements: [AXUIElement])] = []
    private var key: SplitKey?
    private var display: DisplayContext?
    private var ignoreUntil: ContinuousClock.Instant = .now
    private var pending: Task<Void, Never>?
    /// Bumped by every `stop()`, so a debounce or learn begun under an earlier watch never writes.
    private var generation = 0

    init(windows: WindowService, model: SettingsModel) {
        self.windows = windows
        self.model = model
    }

    /// Starts watching `group`, the windows just tiled on `display` as `key`. Replaces any earlier watch.
    /// Moves and resizes before `ignoreUntil` are the Tile's own and are ignored.
    func watch(_ group: [WindowRef], key: SplitKey, display: DisplayContext, ignoreUntil: ContinuousClock.Instant) {
        stop()
        guard model.settings.learnSplits else { return }
        self.key = key
        self.display = display
        self.ignoreUntil = ignoreUntil

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (pid, refs) in Dictionary(grouping: group, by: \.pid) {
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
        display = nil
    }

    fileprivate func handle(_ notification: String) {
        guard key != nil else { return }  // queued before stop()
        if notification == kAXUIElementDestroyedNotification {
            stop()
            return
        }
        guard ContinuousClock.now >= ignoreUntil else { return }
        pending?.cancel()
        let generation = self.generation
        pending = Task { [weak self] in
            do { try await Task.sleep(for: Self.debounce) } catch { return }
            await self?.learnNow(generation)
        }
    }

    private func learnNow(_ generation: Int) async {
        guard generation == self.generation, let key, let display else { return }
        guard model.settings.learnSplits else {
            stop()
            return
        }
        let visible = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                   excluding: Set(model.settings.excludedBundleIDs))
        // A newer move (which cancels this task), a stop or a new watch while reading: the newer state wins.
        guard generation == self.generation, !Task.isCancelled else { return }
        // A window joined, left or moved to another display: this is no longer the arrangement that was tiled.
        guard SplitKey(display: display.id.storageKey, bundleIDs: visible.map(\.window.bundleID)) == key else {
            stop()
            return
        }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let frames = visible.map { (bundleID: $0.window.bundleID, frame: $0.frame) }
        // An arrangement that can't be learned (say, windows overlapping) is skipped; the next adjustment tries again.
        guard case let .success(slots) = SplitLearner.learn(frames, usable: usable, gap: display.profile.gap) else { return }
        let split = LearnedSplit(key: key, slots: slots, updated: Date())
        model.settings.learnedSplits = SplitMemory.upsert(split, into: model.settings.learnedSplits)
        onLearned?("Learned split · \(SplitLabel.apps(key)) · \(SplitLabel.display(key, displays: [display]))")
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
