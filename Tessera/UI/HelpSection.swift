import SwiftUI
import TesseraCore

/// General › Tips: whether tips appear on their own, whether they dim the screen, and seeing them all again.
struct HelpSection: View {
    @Bindable var model: SettingsModel
    /// Set by Show Tips Again; the confirmation stays until the pane is left.
    @State private var tipsReset = false

    var body: some View {
        Section {
            Toggle("Show tips on their own", isOn: $model.settings.help.autoShow).settingAnchor("Show tips on their own")
            Toggle("Dim the screen behind tips", isOn: $model.settings.help.dimScreen).settingAnchor("Dim the screen behind tips")
            HStack {
                Button("Show Tips Again") {
                    model.settings.help.seenMoments = []
                    tipsReset = true
                }
                .disabled(model.settings.help.seenMoments.isEmpty)
                .settingAnchor("Show Tips Again")
                if tipsReset { Caption("Tips will show again.") }
                Spacer()
            }
            .onDisappear { tipsReset = false }
        } header: {
            InfoHeader("Tips", info: "What Just Happened? in the menu bar, or its hotkey, explains the last thing Tessera did. The dimming uses the colour and strength set in Appearance.")
        }
    }
}
