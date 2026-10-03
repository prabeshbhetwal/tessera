import SwiftUI
import TesseraCore

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The menu bar item is AppKit (`StatusItemController`). This scene only supplies the standard main menu
    /// (shown while a Tessera window is open), with its Settings… command opening Tessera's own window.
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.coordinator?.presenter.showSettings() }
                        .keyboardShortcut(",")
                }
            }
    }
}
