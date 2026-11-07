import Foundation
import Testing
@testable import TesseraCore

@Suite struct HelpSettingsTests {
    /// `.defaults` as a file written by a build that predates help: no `help` key, optionally no `explain` binding.
    private func decode(_ s: TesseraSettings, dropHelp: Bool, dropExplain: Bool = true) throws -> TesseraSettings {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        if dropHelp { json.removeValue(forKey: "help") }
        if dropExplain {
            json["hotkeys"] = (json["hotkeys"] as! [[String: Any]]).filter { $0["id"] as? String != "explain" }
        }
        return try SettingsStore.decode(JSONSerialization.data(withJSONObject: json)).settings
    }

    @Test func oldFileWithoutHelpDecodesWithDefaults() throws {
        let s = try decode(.defaults, dropHelp: true, dropExplain: false)
        #expect(s.help.autoShow)
        #expect(s.help.seenMoments.isEmpty)
    }
    @Test func helpWithoutDimScreenDecodesAsTrue() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        var help = json["help"] as! [String: Any]
        help.removeValue(forKey: "dimScreen")
        help["autoShow"] = false
        json["help"] = help
        let s = try SettingsStore.decode(JSONSerialization.data(withJSONObject: json)).settings
        #expect(s.help.dimScreen)
        #expect(!s.help.autoShow)
    }
    @Test func upgradeFileGetsExplainWhenFree() throws {
        let s = try decode(.defaults, dropHelp: true)
        #expect(s.hotkeys.filter { $0.id == "explain" }.count == 1)
    }
    @Test func upgradeFileSkipsWhenChordTaken() throws {
        var s = TesseraSettings.defaults
        s.hotkeys.append(HotkeyBinding(id: "mine", hotkey: HelpDefaults.explainHotkey, command: .undo))
        #expect(!(try decode(s, dropHelp: true)).hotkeys.contains { $0.id == "explain" })
    }
    @Test func currentFileNeverReaddsDeletedExplain() throws {
        #expect(!(try decode(.defaults, dropHelp: false)).hotkeys.contains { $0.id == "explain" })
    }
    @Test func freshDefaultsHoldExplainOnce() {
        let out = HelpDefaults.offeringExplainHotkey(.defaults)
        #expect(out.hotkeys.filter { $0.id == "explain" }.count == 1)
    }
}
