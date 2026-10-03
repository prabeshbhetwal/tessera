import SwiftUI
import TesseraCore

/// Named cycles (M2 spec §4): a hotkey that runs a cycle steps through its targets on repeated presses.
struct CyclesPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            CyclesEditor(cycles: $model.settings.cycles)
            ResetSection { model.settings.cycles = Cycle.defaults }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    CyclesPane(model: SettingsModel())
}
