import SwiftUI
import TesseraCore

/// General › Help: whether tips appear on their own, whether they dim the screen, and seeing them all again.
struct HelpSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section {
            Toggle("Show tips when something new happens", isOn: $model.settings.help.autoShow)
            Toggle("Dim the screen behind tips", isOn: $model.settings.help.dimScreen)
            HStack {
                Button("Show Tips Again") { model.settings.help.seenMoments = [] }
                    .disabled(model.settings.help.seenMoments.isEmpty)
                Spacer()
            }
        } header: {
            Text("Help")
        } footer: {
            Footer("What Just Happened? (⌃⌥/) always works.")
        }
    }
}
