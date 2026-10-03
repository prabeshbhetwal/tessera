import Observation
import TesseraCore

/// Observable wrapper the UI binds to. The coordinator persists and applies every change via `onChange`.
@MainActor @Observable
final class SettingsModel {
    /// Writes of an unchanged value are dropped before Observation sees them, so a binding that
    /// re-writes the same value can never trigger a re-render (and so never a render loop).
    var settings: TesseraSettings {
        get {
            access(keyPath: \.settings)
            return storage
        }
        set {
            guard newValue != storage else { return }
            withMutation(keyPath: \.settings) { storage = newValue }
            onChange?(newValue)
        }
    }

    @ObservationIgnored private var storage: TesseraSettings
    @ObservationIgnored var onChange: (@MainActor (TesseraSettings) -> Void)?

    init(settings: TesseraSettings = .defaults) {
        storage = settings
    }
}
