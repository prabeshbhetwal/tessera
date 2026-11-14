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
    @Test func unknownLookLoadsAsFrosted() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as? [String: Any])
        object["windowMaterial"] = "holographic"
        object["appearance"] = "dark"
        let settings = try SettingsStore.decode(JSONSerialization.data(withJSONObject: object)).settings
        #expect(settings.windowMaterial == .frosted)
        #expect(settings.appearance == .dark, "the rest of the file still loads")
    }

    /// 0.2.0-beta.30 saved "liquidGlass", a look that has since been withdrawn: it loads as Frosted.
    @Test func withdrawnLiquidGlassLoadsAsFrosted() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as? [String: Any])
        object["windowMaterial"] = "liquidGlass"
        #expect(try SettingsStore.decode(JSONSerialization.data(withJSONObject: object)).settings.windowMaterial == .frosted)
    }
}
