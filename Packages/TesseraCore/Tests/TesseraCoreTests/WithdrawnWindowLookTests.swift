import Foundation
import Testing
@testable import TesseraCore

/// 0.2.0-beta.29 to beta.30 saved a Settings window look ("windowMaterial"), since withdrawn: Settings now has one look.
struct WithdrawnWindowLookTests {
    @Test(arguments: ["liquidGlass", "frosted", "solid", "holographic"])
    func savedLookIsIgnoredAndTheRestLoads(look: String) throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as? [String: Any])
        object["windowMaterial"] = look
        object["appearance"] = "dark"
        let settings = try SettingsStore.decode(JSONSerialization.data(withJSONObject: object)).settings
        #expect(settings.appearance == .dark)
    }
}
