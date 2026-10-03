import SwiftUI
import TesseraCore

@main
struct TesseraApp: App {
    @State private var model = SettingsModel()

    var body: some Scene {
        MenuBarExtra("Tessera", systemImage: "square.grid.3x2") {
            Button("Quit Tessera") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
