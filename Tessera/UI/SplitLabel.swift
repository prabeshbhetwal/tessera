import AppKit
import TesseraCore

/// Human-readable names for a learned split, for messages and the Splits pane.
@MainActor
enum SplitLabel {
    /// "Chrome ×2, Slack": each app once, in the key's order, with a count when it has several windows.
    static func apps(_ key: SplitKey) -> String {
        var names: [(name: String, count: Int)] = []
        for app in key.apps {
            let name = appName(app)
            if let index = names.firstIndex(where: { $0.name == name }) {
                names[index].count += 1
            } else {
                names.append((name, 1))
            }
        }
        return names.map { $0.count > 1 ? "\($0.name) ×\($0.count)" : $0.name }.joined(separator: ", ")
    }

    /// The name of the key's display, or "Disconnected display" when it is not among `displays` or has no screen.
    static func display(_ key: SplitKey, displays: [DisplayContext]) -> String {
        guard let display = displays.first(where: { $0.id.storageKey == key.display }),
              let screen = NSScreen.screens.first(where: { $0.frame == display.frame }) else {
            return "Disconnected display"
        }
        return screen.localizedName
    }

    private static func appName(_ bundleID: String) -> String {
        guard bundleID != SplitKey.unknownApp else { return "Unknown app" }
        let name = ExcludedAppsPane.name(for: bundleID)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
