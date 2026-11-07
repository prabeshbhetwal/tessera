import Foundation
import Testing
@testable import TesseraCore

@Suite struct HelpSettingsTests {
    @Test func oldFileWithoutHelpDecodesWithDefaults() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        json.removeValue(forKey: "help")
        let (s, _) = try SettingsStore.decode(JSONSerialization.data(withJSONObject: json))
        #expect(s.help.autoShow)
        #expect(s.help.seenMoments.isEmpty)
    }
    @Test func offerAddsExplainWhenFree() {
        var s = TesseraSettings.defaults
        s.hotkeys.removeAll { $0.id == "explain" }
        let out = HelpDefaults.offeringExplainHotkey(s)
        #expect(out.hotkeys.filter { $0.id == "explain" }.count == 1)
        #expect(out.help.explainHotkeyOffered)
    }
    @Test func offerSkipsWhenChordTaken() {
        var s = TesseraSettings.defaults
        s.hotkeys.removeAll { $0.id == "explain" }
        s.hotkeys.append(HotkeyBinding(id: "mine", hotkey: HelpDefaults.explainHotkey, command: .undo))
        let out = HelpDefaults.offeringExplainHotkey(s)
        #expect(!out.hotkeys.contains { $0.id == "explain" })
        #expect(out.help.explainHotkeyOffered)
    }
    @Test func offerNeverReaddsAfterRemoval() {
        var s = TesseraSettings.defaults
        s.hotkeys.removeAll { $0.id == "explain" }
        s.help.explainHotkeyOffered = true
        #expect(!HelpDefaults.offeringExplainHotkey(s).hotkeys.contains { $0.id == "explain" })
    }
    @Test func freshDefaultsHoldExplainOnce() {
        let out = HelpDefaults.offeringExplainHotkey(.defaults)
        #expect(out.hotkeys.filter { $0.id == "explain" }.count == 1)
    }
}
