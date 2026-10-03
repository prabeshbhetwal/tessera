import Foundation
import Testing
@testable import TesseraCore

@Suite struct ModelTests {
    @Test func defaultsMatchSpec() throws {
        let s = TesseraSettings.defaults
        #expect(s.schemaVersion == 2)
        #expect(s.trigger.keyCodes == [59, 58, 55])
        #expect(s.sizing == SizingConstants.default)
        #expect(s.sizing.idealColumnWidth == 768)
        #expect(s.sizing.minColumnWidth == 640)
        #expect(s.sizing.maxColumnWidth == 1280)
        #expect(s.sizing.minRowHeight == 440)
        #expect(s.sizing.maxColumns == 8)
        #expect(s.defaultGap == 8)
        #expect(s.defaultPadding == 8)
        #expect(s.ring.deadZone == 10)
        #expect(s.ring.flickDistance == 90)
        #expect(s.ring.wedges.count == 8)
        #expect(s.ring.wedges.first == .maximize)
        #expect(s.ring.wedges[4] == .center)
        #expect(s.ring.topBand == 0.30)
        #expect(s.ring.bottomBand == 0.30)
        #expect(s.preview.springResponse == 0.18)
        #expect(s.preview.showThumbnail && s.preview.showLabel && s.preview.showNeighbours && s.preview.morph)
    }

    @Test func storageKey() {
        #expect(DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil).storageKey == "1-2-3")
        #expect(DisplayID(vendor: 1, model: 2, serial: 0, uuid: "ABC").storageKey == "uuid:ABC")
    }

    @Test func settingsRoundTrip() throws {
        var s = TesseraSettings.defaults
        s.displayOverrides["1-2-3"] = DisplayProfile(columns: 6, isUserOverride: true)
        s.customThemes = [.glass]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(TesseraSettings.self, from: data)
        #expect(back == s)
    }

    @Test func builtInThemes() {
        #expect(Theme.builtIn.map(\.name) == ["Default", "Minimal", "Glass"])
        #expect(Theme.minimal.preview.showThumbnail == false)
    }
}
