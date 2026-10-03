// TEMPORARY STUB — coordinator deletes at merge
import Foundation
import TesseraCore

/// Track H signature (`TesseraCore/Keyboard/HotkeyTable.swift`). Only `conflicts` is used by the UI.
struct HotkeyTable: Sendable {
    init(_ bindings: [HotkeyBinding]) {}

    static func conflicts(_ bindings: [HotkeyBinding], chord: TriggerChord, systemHotkeys: Set<Hotkey>) -> [String: String] {
        var result: [String: String] = [:]
        for b in bindings where b.enabled {
            if bindings.contains(where: { $0.id != b.id && $0.enabled && $0.hotkey == b.hotkey }) {
                result[b.id] = "Another binding uses the same keys."
            } else if systemHotkeys.contains(b.hotkey) {
                result[b.id] = "macOS already uses these keys."
            }
        }
        return result
    }
}

/// Track J signature (`Tessera/Automation/CLIInstaller.swift`).
@MainActor
enum CLIInstaller {
    static var isInstalled: Bool { false }

    static func install() -> Result<URL, Error> {
        .failure(CocoaError(.featureUnsupported))
    }
}
