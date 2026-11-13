import Foundation
import Testing
@testable import TesseraCore

struct WindowMaterialTests {
    @Test func everyLookRoundTrips() throws {
        for look in WindowMaterial.allCases {
            var s = TesseraSettings.defaults
            s.windowMaterial = look
            #expect(try SettingsStore.decode(JSONEncoder().encode(s)).settings.windowMaterial == look)
        }
    }

    /// A look from a newer build must not set the whole settings file aside.
    @Test func unknownLookLoadsAsLiquidGlass() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as? [String: Any])
        object["windowMaterial"] = "holographic"
        object["appearance"] = "dark"
        let settings = try SettingsStore.decode(JSONSerialization.data(withJSONObject: object)).settings
        #expect(settings.windowMaterial == .liquidGlass)
        #expect(settings.appearance == .dark, "the rest of the file still loads")
    }
}
