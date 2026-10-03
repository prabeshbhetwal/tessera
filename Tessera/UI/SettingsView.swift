import Observation
import SwiftUI
import TesseraCore

/// Settings panes in tab order; ⌘1–8 selects them.
enum SettingsPane: Int, CaseIterable, Hashable {
    case general, shortcuts, displays, ring, preview, appearance, excludedApps, about
}

/// Which pane is showing. Owned by `WindowPresenter` so menu items can open a specific pane.
@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
}

/// Settings window root: one tab per pane (spec §6.1, M2 §6).
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Bindable var navigation: SettingsNavigation
    var displays: [DisplayContext]

    var body: some View {
        TabView(selection: $navigation.pane) {
            Tab("General", systemImage: "gearshape", value: .general) { GeneralPane(model: model) }
            Tab("Shortcuts", systemImage: "command", value: .shortcuts) { ShortcutsPane(model: model) }
            Tab("Displays", systemImage: "display.2", value: .displays) { DisplaysPane(model: model, displays: displays) }
            Tab("Ring", systemImage: "circle.dashed", value: .ring) { RingPane(model: model) }
            Tab("Preview", systemImage: "rectangle.dashed", value: .preview) { PreviewPane(model: model) }
            Tab("Appearance", systemImage: "paintpalette", value: .appearance) { AppearancePane(model: model) }
            Tab("Excluded Apps", systemImage: "nosign", value: .excludedApps) { ExcludedAppsPane(model: model) }
            Tab("About", systemImage: "info.circle", value: SettingsPane.about) { AboutPane() }
        }
        .background {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                KeyCommand(KeyEquivalent(Character("\(pane.rawValue + 1)"))) { navigation.pane = pane }
            }
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 560, idealHeight: 680)
    }
}

#Preview {
    SettingsView(model: SettingsModel(), navigation: SettingsNavigation(), displays: [])
}
