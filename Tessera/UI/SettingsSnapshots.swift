#if DEBUG
import AppKit
import SwiftUI
import TesseraCore

/// Debug builds only. With `TESSERA_SETTINGS_SNAPSHOTS=<folder>` set, renders every Settings pane, light and dark,
/// to PNGs in that folder and quits, before anything else starts (no permissions, no event tap, no windows moved).
/// Settings are the defaults, in memory: nothing is read from or written to the settings file.
@MainActor
enum SettingsSnapshots {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["TESSERA_SETTINGS_SNAPSHOTS"] else { return false }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = SettingsModel()
        let visible = CGRect(x: 0, y: 0, width: 3440, height: 1407)
        let range = SizingRule.range(for: visible.size, constants: model.settings.sizing)
        let displays = [DisplayContext(
            id: DisplayID(vendor: 0, model: 0, serial: 0, uuid: "snapshot"), frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            visibleFrame: visible, range: range, profile: .auto(range: range, gap: 8, padding: 8))]
        for (scheme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            for pane in SettingsPane.allCases {
                let navigation = SettingsNavigation()
                navigation.pane = pane
                let host = NSHostingView(rootView: SettingsView(model: model, navigation: navigation, displays: displays)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme)
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -20_000, y: 0))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let file = folder.appendingPathComponent("\(pane.key)-\(name).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: file)
                }
                window.orderOut(nil)
            }
        }
        NSApp.terminate(nil)
        return true
    }
}
#endif
