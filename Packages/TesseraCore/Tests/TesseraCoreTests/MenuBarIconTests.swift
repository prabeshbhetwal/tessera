import Foundation
import Testing

@testable import TesseraCore

/// Settings bytes with `menuBarIcon` set to `raw`, as an older or hand-edited file would hold it.
private func settingsData(menuBarIcon raw: String) throws -> Data {
    let encoded = try JSONEncoder().encode(TesseraSettings.defaults)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["menuBarIcon"] = raw
    return try JSONSerialization.data(withJSONObject: object)
}

struct MenuBarIconTests {
    /// Files from before the glyphs stored SF Symbol names; each loads as its nearest glyph.
    @Test(arguments: [
        ("square.grid.3x2", MenuBarIcon.tiles), ("rectangle.split.3x1", .columns), ("rectangle.split.2x1", .split),
        ("square.grid.2x2", .quarters), ("macwindow", .badge), ("circle.dashed", .ring),
    ])
    func oldSymbolNamesLoadAsTheirGlyph(name: String, icon: MenuBarIcon) throws {
        #expect(try SettingsStore.decode(settingsData(menuBarIcon: name)).settings.menuBarIcon == icon)
    }

    @Test func unknownPictureLoadsAsTilesAndKeepsTheRest() throws {
        let settings = try SettingsStore.decode(settingsData(menuBarIcon: "star.fill")).settings
        #expect(settings.menuBarIcon == .tiles)
        #expect(settings == TesseraSettings.defaults)
    }

    @Test func everyIconRoundTrips() throws {
        for icon in MenuBarIcon.allCases {
            var s = TesseraSettings.defaults
            s.menuBarIcon = icon
            #expect(try SettingsStore.decode(JSONEncoder().encode(s)).settings.menuBarIcon == icon)
        }
    }
}
