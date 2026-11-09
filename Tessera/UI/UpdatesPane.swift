import SwiftUI
import TesseraCore

/// Settings › Updates: the one place for update settings and the manual check (the menu bar item is the other way
/// to check). The toggles only write settings; `AppDelegate` applies them to Sparkle on change.
struct UpdatesPane: View {
    @Bindable var model: SettingsModel
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        Form {
            Section {
                // Re-rendered each minute so "5 minutes ago" stays true while the settings window stays open.
                TimelineView(.everyMinute) { _ in
                    LabeledContent("Last checked",
                                   value: updates.lastUpdateCheckDate?.formatted(.relative(presentation: .named)) ?? "Never")
                }
                // Read when the pane draws: checks are refused until the person reopens Tessera.
                if updates.replacedSinceLaunch {
                    Label(UpdateService.replacedMessage, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
                HStack {
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                    Spacer()
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $model.settings.updates.checkAutomatically)
                Picker("Frequency", selection: $model.settings.updates.interval) {
                    ForEach(UpdateInterval.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!model.settings.updates.checkAutomatically)
                // Sparkle ignores it while checks are off.
                Toggle("Download and install automatically", isOn: $model.settings.updates.installAutomatically)
                    .disabled(!model.settings.updates.checkAutomatically)
                Toggle("Include beta versions", isOn: $model.settings.updates.includeBetas)
            } header: {
                Text("Automatic updates")
            } footer: {
                Footer("Updates are verified before they install. Beta versions get new features first and may be less stable.")
            }

            ResetSection { model.settings.updates = UpdateSettings() }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    UpdatesPane(model: SettingsModel())
}
