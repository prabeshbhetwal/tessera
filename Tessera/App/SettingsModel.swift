import Observation
import TesseraCore

/// Observable wrapper the UI binds to. The coordinator persists and applies every change via `onChange`.
@MainActor @Observable
final class SettingsModel {
    var settings: TesseraSettings {
        didSet { if settings != oldValue { onChange?(settings) } }
    }

    @ObservationIgnored var onChange: (@MainActor (TesseraSettings) -> Void)?

    init(settings: TesseraSettings = .defaults) {
        self.settings = settings
    }
}
