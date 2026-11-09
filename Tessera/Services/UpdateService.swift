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

    static let replacedMessage =
        "Tessera was replaced while it was open. Quit Tessera and open it again, then check for updates."

    /// True when the app on disk is not the build that is running (rebuilt in place, or a newer copy dragged over
    /// it). Sparkle's check compares the appcast against the version loaded at launch, but its installer compares
    /// against the app on disk, so they disagree: the check offers a release the installer then refuses as a
    /// downgrade, which shows only "An error occurred while running the updater".
    var replacedSinceLaunch: Bool {
        guard let onDisk = Self.bundleVersionOnDisk() else { return false }
        return onDisk != Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Refuses every check while `replacedSinceLaunch`: a manual check shows `replacedMessage`, a scheduled one
    /// fails silently and Settings › Updates says why.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard replacedSinceLaunch else { return }
        throw NSError(domain: "com.prabeshbhetwal.Tessera.updates", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: Self.replacedMessage])
    }

    /// Read from the file: `Bundle` keeps the Info.plist it loaded at launch for the life of the process.
    private static func bundleVersionOnDisk() -> String? {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleVersion"] as? String
    }

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
