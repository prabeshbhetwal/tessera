import SwiftUI
import TesseraCore

/// The demo beside a pane's form: a mock desktop that shows what the pane's settings do, live.
/// General, Excluded Apps, Updates and About have none; their form takes the full width.
struct SettingsDemo: View {
    let pane: SettingsPane
    let settings: TesseraSettings

    static func exists(for pane: SettingsPane) -> Bool {
        switch pane {
        case .ring, .shortcuts, .cycles, .displays, .splits, .overlay, .motion: true
        case .general, .excludedApps, .updates, .about: false
        }
    }

    var body: some View {
        switch pane {
        case .ring: RingDemo(settings: settings)
        case .shortcuts: ShortcutsDemo(settings: settings)
        case .cycles: CyclesDemo(settings: settings)
        case .displays: DisplaysDemo(settings: settings)
        case .splits: SplitsDemo(settings: settings)
        case .motion: MotionDemo(settings: settings)
        case .overlay:
            DemoColumn(title: "Sample") {
                OverlaySample(ring: settings.ring, theme: settings.activeTheme)
                Caption("The ring with Right picked, the window it moves from, and the preview where it lands.")
            }
        case .general, .excludedApps, .updates, .about: EmptyView()
        }
    }
}
