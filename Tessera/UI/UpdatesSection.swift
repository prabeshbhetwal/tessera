import SwiftUI
import TesseraCore

/// General › Updates. The toggles only write settings; `AppDelegate` applies them to Sparkle on change.
struct UpdatesSection: View {
    @Bindable var model: SettingsModel
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $model.settings.updates.checkAutomatically).settingAnchor("Check for updates automatically")
            Picker("Frequency", selection: $model.settings.updates.interval) {
                ForEach(UpdateInterval.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!model.settings.updates.checkAutomatically)
            .settingAnchor("Frequency")
            // Sparkle ignores it while checks are off.
            Toggle("Download and install automatically", isOn: $model.settings.updates.installAutomatically).settingAnchor("Download and install automatically")
                .disabled(!model.settings.updates.checkAutomatically)
            Toggle("Include beta versions", isOn: $model.settings.updates.includeBetas).settingAnchor("Include beta versions")
            // Re-rendered each minute so "5 minutes ago" stays true while the settings window stays open.
            TimelineView(.everyMinute) { _ in
                LabeledContent("Last checked",
                               value: updates.lastUpdateCheckDate?.formatted(.relative(presentation: .named)) ?? "Never")
            }
            HStack {
                Button("Check Now") { updates.checkForUpdates() }.settingAnchor("Check Now")
                    .disabled(!updates.canCheckForUpdates)
                Spacer()
            }
        } header: {
            Text("Updates")
        } footer: {
            Footer("Updates are verified before they install. Beta versions get new features first and may be less stable.")
        }
    }
}
