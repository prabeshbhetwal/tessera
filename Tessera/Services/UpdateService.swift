import Combine
import Foundation
import Sparkle
import TesseraCore

/// Applies the user's `UpdateSettings` to Sparkle and exposes what the UI needs: the manual check, whether one
/// can start, when the last one ran and whether a found update is waiting. One instance per process, reached as
/// `UpdateService.shared`. Sparkle starts on the first `apply(_:)`, so it never runs on stale defaults.
@MainActor
final class UpdateService: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate,
    ObservableObject {
    static let shared = UpdateService()

    /// Mirrors `SPUUpdater.canCheckForUpdates` (KVO): false while a check or update session is running.
    @Published private(set) var canCheckForUpdates = false

    /// True while a scheduled check's update alert waits unseen (a menu bar app's alert can sit behind other
    /// windows). Cleared once the person gives the alert attention or the session ends.
    @Published private(set) var updateWaiting = false

    /// Pass-through: Sparkle documents no KVO for it, so views re-render when `canCheckForUpdates` flips
    /// at the end of a check.
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    /// Called when the person changes "install automatically" in Sparkle's own update alert, so the
    /// settings stay the one source of truth. Set by the app delegate.
    var onInstallAutomaticallyChange: ((Bool) -> Void)?

    /// What `apply(_:)` last wrote; nil until the first call, which also starts Sparkle.
    private var lastApplied: UpdateSettings?
    private var channels: Set<String> = []
    private var subscriptions: Set<AnyCancellable> = []
    // Lazy: the delegates (self) can only be passed once `super.init()` has run.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
    )

    private override init() {
        super.init()
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        // The alert's checkbox writes Sparkle's own preference. Delivered on main, then read live, so a value
        // queued during `apply(_:)` and already superseded is never written back.
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installAutomaticallyChanged() }
            .store(in: &subscriptions)
    }

    func apply(_ settings: UpdateSettings) {
        // Unrelated settings edits must not make Sparkle rewrite its preferences and reschedule its check.
        guard settings != lastApplied else { return }
        let starting = lastApplied == nil
        // Before the setters: their own change notifications are echoes of this value.
        lastApplied = settings
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = settings.checkAutomatically
        updater.updateCheckInterval = settings.interval.seconds
        updater.automaticallyDownloadsUpdates = settings.installAutomatically
        channels = settings.allowedChannels
        if starting { controller.startUpdater() }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    private func installAutomaticallyChanged() {
        let updater = controller.updater
        // Sparkle forces the value off while checks are off; that is not the person's choice.
        guard updater.automaticallyChecksForUpdates, let applied = lastApplied,
              updater.automaticallyDownloadsUpdates != applied.installAutomatically else { return }
        onInstallAutomaticallyChange?(updater.automaticallyDownloadsUpdates)
    }

    // SPUUpdaterDelegate is `NS_SWIFT_UI_ACTOR` (main-actor isolated), so no lock is needed.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channels }

    // MARK: - SPUStandardUserDriverDelegate (called on the main thread; `@preconcurrency` checks it)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !state.userInitiated { updateWaiting = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateWaiting = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateWaiting = false
    }
}
