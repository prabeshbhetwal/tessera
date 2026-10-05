import Combine
import Sparkle
import TesseraCore

/// Applies the user's `UpdateSettings` to Sparkle and exposes what the UI needs: the manual check, whether one
/// can start, and when the last one ran. One instance per process, reached as `UpdateService.shared`
/// (AppDelegate touches it at launch, which starts Sparkle's scheduler).
@MainActor
final class UpdateService: NSObject, SPUUpdaterDelegate, ObservableObject {
    static let shared = UpdateService()

    /// Mirrors `SPUUpdater.canCheckForUpdates` (KVO): false while a check or update session is running.
    @Published private(set) var canCheckForUpdates = false

    /// Pass-through: Sparkle documents no KVO for it, so views re-render when `canCheckForUpdates` flips
    /// at the end of a check.
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    private var channels: Set<String> = []
    // Lazy: the delegate (self) can only be passed once `super.init()` has run.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
    )

    private override init() {
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func apply(_ settings: UpdateSettings) {
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = settings.checkAutomatically
        updater.updateCheckInterval = settings.interval.seconds
        updater.automaticallyDownloadsUpdates = settings.installAutomatically
        channels = settings.allowedChannels
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // SPUUpdaterDelegate is `NS_SWIFT_UI_ACTOR` (main-actor isolated), so no lock is needed.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channels }
}
