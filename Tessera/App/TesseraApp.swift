import SwiftUI
import TesseraCore

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(isInserted: showIcon) {
            MenuContent(delegate: delegate)
        } label: {
            if delegate.state.accessibilityGranted {
                Image(systemName: "square.grid.3x2")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Tessera needs permission")
            }
        }
    }

    private var showIcon: Binding<Bool> {
        Binding(
            get: { delegate.model.settings.showMenuBarIcon },
            set: { delegate.model.settings.showMenuBarIcon = $0 }
        )
    }
}

private struct MenuContent: View {
    let delegate: AppDelegate

    var body: some View {
        if !delegate.state.accessibilityGranted {
            Button("Permission needed…") { delegate.coordinator?.presenter.showOnboarding() }
            Divider()
        }
        Button("Settings…") { delegate.coordinator?.presenter.showSettings() }
            .keyboardShortcut(",")
        Button("Undo last move") { delegate.coordinator?.undoLast() }
            .disabled(!delegate.state.accessibilityGranted)
        Divider()
        Button("Quit Tessera") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
