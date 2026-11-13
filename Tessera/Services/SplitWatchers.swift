import AppKit
import os
import TesseraCore

/// One `SplitWatcher` per display, kept armed so a hand adjustment reflows the neighbours without a Tile first.
/// Once Tessera's moves settle, at launch, after a display change and after a settings change, every display whose
/// windows sit side by side (two or more that `SplitLearner` accepts as a split) is watched. A display already watching
/// that same group keeps its watch, so its baseline and Tile Evenly's no-learn watch survive.
@MainActor
final class SplitWatchers {
    var onLearned: ((String) -> Void)? {
        didSet { for watcher in watchers.values { watcher.onLearned = onLearned } }
    }
    var onHelpEvent: ((HelpEvent) -> Void)? {
        didSet { for watcher in watchers.values { watcher.onHelpEvent = onHelpEvent } }
    }

    let windows: WindowService
    let displays: DisplayService
    let model: SettingsModel
    var lastLayoutSettings: TesseraSettings
    /// Keyed by `DisplayID.storageKey`.
    private(set) var watchers: [String: SplitWatcher] = [:]
    private(set) var ownMoves = 0
    var pendingArm: Task<Void, Never>?
    /// Covering the space a closed window left (see `fillSoon`), keyed by `DisplayID.storageKey`.
    var pendingFills: [String: Task<Void, Never>] = [:]
    var fillIDs: [String: UUID] = [:]
    var fillGroups: [String: [(window: WindowRef, frame: CGRect)]] = [:]
    /// Tiling a newly opened window in (see `joinSoon`), one look per app, so another app's activation never cuts a
    /// look short.
    var pendingJoins: [pid_t: Task<Void, Never>] = [:]
    /// Apps whose launch or restored window a look in `pendingJoins` is still waiting for, so their own activation
    /// doesn't replace that look.
    var firstWindowLooks: Set<pid_t> = []
    /// Creation events can replace the same app's queued look; every unprocessed newcomer must survive replacement.
    var pendingNewWindows: [pid_t: Set<CGWindowID>] = [:]
    /// When each app was last unhidden: its windows reappearing are not new windows joining.
    var unhidden: [pid_t: Date] = [:]
    /// Groups last arranged by Tile Evenly: a re-arm keeps them from learning, so the stored split survives.
    var noLearn: Set<SplitKey> = []
    /// Minimised out of a group whose space the rest covered; tiled back in when restored (see `joinSoon`).
    let minimisedWindows = MinimisedWindows()
    /// By bundle ID: an app whose window closed out of a group whose space the rest covered, with the windows it left
    /// and their display. Relaunched, its window joins them again, even when only one is left (a lone window isn't
    /// watched, so `splitNewWindowScope`'s tiled displays would miss it).
    var closedOutOf: [String: [String: [WindowRef]]] {
        get { workspaceStore.closedContexts(active: scopedWorkspaceKeys()) }
        set { workspaceStore.replaceClosedContexts(newValue, active: scopedWorkspaceKeys()) }
    }
    let workspaceStore = SplitWorkspaceStore()
    var activeWorkspaceKeys: [String: SplitWorkspaceStore.Key] = [:]
    var watchedDisplays: [String: DisplayContext] = [:]
    var pendingResumes: [String: Task<Void, Never>] = [:]
    var resumeIDs: [String: UUID] = [:]
    var startupRestore: Task<Void, Never>?
    var convergenceTask: Task<Void, Never>?
    var convergenceID: UUID?
    let lifecycle: WindowLifecycleMonitor

    let lifecycleLog = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "split-lifecycle")
    var missingAttempts: [String: Int] = [:]
    private var lifecycleTimer: Timer?
    var reconciliation: Task<Void, Never>?
    private var arming = 0
    private var nextReconciliation: [String: ContinuousClock.Instant] = [:]

    init(windows: WindowService, displays: DisplayService, model: SettingsModel,
         lifecycle: WindowLifecycleMonitor = WindowLifecycleMonitor()) {
        self.lifecycle = lifecycle
        self.windows = windows
        self.displays = displays
        self.model = model
        self.lastLayoutSettings = model.settings
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMissingWindows() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        lifecycleTimer = timer
        lifecycle.onCreated = { [weak self] pid, id in
            self?.joinSoon(pid: pid, launched: false, windowCreated: true, createdWindowID: id)
        }
        lifecycle.onFocusChanged = { [weak self] pid in
            self?.joinSoon(pid: pid, launched: false)
            self?.armSoon()
        }
        connectNotifications()
    }

    /// Watches `group` on `display`, replacing that display's watch. `learns` false reflows neighbours but never saves
    /// the arrangement as a split (Tile Evenly).
    func watch(_ group: [(window: WindowRef, frame: CGRect)], display: DisplayContext, learns: Bool = true) {
        nextReconciliation[display.id.storageKey] = nil
        missingAttempts[display.id.storageKey] = nil
        guard rememberWorkspace(group, display: display) else { return }
        lifecycle.remember(group.map(\.window))
        let key = SplitKey(group, on: display)
        if learns { noLearn.remove(key) } else { noLearn.insert(key) }
        let watcher = watcher(for: display)
        if watcher.watches(group) { watcher.updateBaseline(group, learns: learns) }
        else { watcher.watch(group, display: display, learns: learns) }
    }

    func save(_ found: [(window: WindowRef, frame: CGRect)], display: DisplayContext)
        -> Result<(key: SplitKey, changed: Bool), SplitRejection> {
        watcher(for: display).save(found, display: display)
    }

    /// Stops every display's watch and any pending re-arm.
    func stop() {
        convergenceTask?.cancel(); convergenceTask = nil; convergenceID = nil
        startupRestore?.cancel()
        startupRestore = nil
        workspaceStore.removeAll()
        activeWorkspaceKeys = [:]
        watchedDisplays = [:]
        minimisedWindows.forgetAll()
        cancelPendingWork()
        for watcher in watchers.values { watcher.stop() }
    }

    /// Undo cancels queued layout work while keeping lifecycle notifications subscribed.
    func cancelPendingWork() {
        for task in pendingResumes.values { task.cancel() }
        pendingResumes = [:]
        resumeIDs = [:]
        nextReconciliation = [:]
        missingAttempts = [:]
        for watcher in watchers.values { watcher.cancelAdjustment() }
        reconciliation?.cancel()
        reconciliation = nil
        pendingArm?.cancel()
        pendingArm = nil
        for task in pendingFills.values { task.cancel() }
        pendingFills = [:]
        fillIDs = [:]
        fillGroups = [:]
        for task in pendingJoins.values { task.cancel() }
        pendingJoins = [:]
        firstWindowLooks = []
        pendingNewWindows = [:]
    }

    /// See `SplitWatcher.beginOwnMove`. Every display hears it: a move can cross displays.
    func beginOwnMove() {
        ownMoves += 1
        pendingArm?.cancel()
        for watcher in watchers.values { watcher.beginOwnMove() }
    }

    func endOwnMove() {
        ownMoves -= 1
        for watcher in watchers.values { watcher.endOwnMove() }
        if ownMoves == 0 { armSoon() }
    }

    /// Re-reads every display after `delay` and watches the ones whose windows sit side by side.
    func armSoon(after delay: Duration = SplitWatcher.settle) {
        pendingArm?.cancel()
        pendingArm = Task { [weak self] in
            await WindowMutationScope.$ticket.withValue(nil) {
                do { try await Task.sleep(for: delay) } catch { return }
                await self?.armAll()
            }
        }
    }

    private func armAll() async {
        arming += 1
        defer { arming -= 1 }
        guard model.settings.learnSplits, Permissions.isAccessibilityTrusted else { return }
        lifecycle.refresh()
        for display in displays.displays {
            await readAndArm(display)
        }
    }

    private func checkMissingWindows() {
        guard model.settings.learnSplits, ownMoves == 0, arming == 0, reconciliation == nil else { return }
        retryPendingRecoveries()
        let ticket = windows.mutationContext.capture()
        let groups = watchers.values.filter {
            !$0.watched.isEmpty
                && !$0.watched.contains { model.settings.excludedBundleIDs.contains($0.bundleID ?? "") }
                && ($0.key.flatMap { nextReconciliation[$0.display] } ?? .now) <= .now
        }.map { ($0, $0.watched, $0.revision) }
        guard !groups.isEmpty else { return }
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = Set(rows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        guard groups.contains(where: { $0.1.contains { $0.windowID.map { !visible.contains($0) } ?? false } }) else { return }
        reconciliation = Task { [weak self] in
            defer { if !Task.isCancelled { self?.reconciliation = nil } }
            await WindowMutationScope.$ticket.withValue(ticket) {
                guard let self else { return }
                for (watcher, observed, revision) in groups {
                    var removed: [Bool] = []
                    for window in observed where window.windowID.map({ !visible.contains($0) }) == true {
                        if let kind = await self.windows.removalKind(of: window) { removed.append(kind) }
                    }
                    guard !Task.isCancelled, self.ownMoves == 0 else { return }
                    guard !observed.contains(where: { self.model.settings.excludedBundleIDs.contains($0.bundleID ?? "") }) else { continue }
                    guard let displayKey = watcher.key?.display,
                          self.windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { continue }
                    if watcher.revision == revision, watcher.watched == observed, !removed.isEmpty {
                        self.lifecycleLog.notice("Reconciled window removal from WindowServer state")
                        watcher.closed(minimised: removed.allSatisfy { $0 })
                    } else if watcher.revision == revision, let key = watcher.key {
                        // Unknown/hung windows retain membership without repeated AX traffic every second.
                        // Authoritative AX and Workspace events still act immediately.
                        self.nextReconciliation[key.display] = .now + .seconds(5)
                    }
                }
            }
        }
    }

    func retireWatcher(_ key: String) {
        watchers.removeValue(forKey: key)?.stop()
        watchedDisplays[key] = nil
        activeWorkspaceKeys[key] = nil
    }

    private func watcher(for display: DisplayContext) -> SplitWatcher {
        let id = display.id.storageKey
        if let existing = watchers[id] { return existing }
        let watcher = SplitWatcher(windows: windows, displays: displays, model: model)
        watcher.onLearned = onLearned
        watcher.onHelpEvent = onHelpEvent
        // A window joined, left or closed: watch whatever the display holds now.
        watcher.onEnded = { [weak self] in self?.armSoon() }
        watcher.onReflowBegan = { [weak self] in self?.beginOwnMove() }
        watcher.onReflowEnded = { [weak self] in self?.endOwnMove() }
        watcher.onWindowClosed = { [weak self] group, displayKey, minimised, baselineAt in
            self?.fillSoon(group, displayKey: displayKey, minimised: minimised, baselineAt: baselineAt)
        }
        watcher.onHandBegan = { [weak self] in self?.handAdjusted(display.id.storageKey) }
        watcher.onManualDeparture = { [weak self] in self?.relinquish([display.id.storageKey], windows: []) }
        // Moves already in flight count for the new watcher too; `endOwnMove` balances them.
        for _ in 0..<ownMoves { watcher.beginOwnMove() }
        // Created after the moves that called for it: their late notifications still count as Tessera's.
        watcher.beginOwnMove()
        watcher.endOwnMove()
        watchers[id] = watcher
        return watcher
    }
}
