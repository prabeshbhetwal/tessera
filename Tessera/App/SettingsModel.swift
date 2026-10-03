import Observation
import TesseraCore

/// Observable wrapper the UI binds to. Persistence is wired in Track F via SettingsStore.
@MainActor @Observable
final class SettingsModel {
    var settings: TesseraSettings

    init(settings: TesseraSettings = .defaults) {
        self.settings = settings
    }
}
