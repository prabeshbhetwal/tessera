import SwiftUI
import TesseraCore

/// Named cycles (M2 spec §4): a hotkey that runs a cycle steps through its targets on repeated presses.
struct CyclesPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            CyclesEditor(cycles: Binding(get: { model.settings.cycles }, set: model.updateCycles))
            ResetSection { model.updateCycles(Cycle.defaults) }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    CyclesPane(model: SettingsModel())
}
