import SwiftUI
import TesseraCore

/// Settings window root: one tab per pane (spec §6.1).
struct SettingsView: View {
    @Bindable var model: SettingsModel
    var displays: [DisplayContext]

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralPane(model: model) }
            Tab("Displays", systemImage: "display.2") { DisplaysPane(model: model, displays: displays) }
            Tab("Ring", systemImage: "circle.dashed") { RingPane(model: model) }
            Tab("Preview", systemImage: "rectangle.dashed") { PreviewPane(model: model) }
            Tab("Appearance", systemImage: "paintpalette") { AppearancePane(model: model) }
            Tab("Excluded Apps", systemImage: "nosign") { ExcludedAppsPane(model: model) }
            Tab("About", systemImage: "info.circle") { AboutPane() }
        }
        .frame(minWidth: 620, idealWidth: 640, minHeight: 560, idealHeight: 640)
    }
}

#Preview {
    SettingsView(model: SettingsModel(), displays: [])
}
