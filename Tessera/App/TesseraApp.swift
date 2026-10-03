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

    /// One-way on purpose. macOS hides/shows status items itself (crowded or notched menu bars) and SwiftUI
    /// writes those flips back through `isInserted`. Writing them into settings re-rendered the scene, which
    /// re-set visibility, which wrote again: an endless loop that froze the app. Only Settings changes this.
    private var showIcon: Binding<Bool> {
        Binding(
            get: { delegate.model.settings.showMenuBarIcon },
            set: { _ in }
        )
    }
}

private struct MenuContent: View {
    let delegate: AppDelegate

    var body: some View {
        // Plain Text in a menu renders as a disabled line: a one-line reminder of how to use the app.
        if delegate.state.accessibilityGranted {
            Text("Hold \(ModifierKey.describe(delegate.model.settings.trigger.keyCodes)) to snap")
            Divider()
            Button("Undo last move") { delegate.coordinator?.undoLast() }
            Divider()
            Button("Settings…") { delegate.coordinator?.presenter.showSettings() }
                .keyboardShortcut(",")
            Button("Shortcuts…") { delegate.coordinator?.presenter.showSettings(pane: .shortcuts) }
        } else {
            // Nothing works without Accessibility, so setup is the only thing on offer.
            Text("Accessibility permission needed")
            Button("Finish setup…") {
                delegate.coordinator?.presenter.showOnboarding(startStep: OnboardingView.accessibilityStep)
            }
        }
        Divider()
        Button("Quit Tessera") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
