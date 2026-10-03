import Foundation
import Testing
@testable import TesseraCore

@Suite struct OverlayOptionsTests {
    /// Files written before the preview style and outline options existed load as the tinted box,
    /// with no current-window outline and no boundary circle — even if they had `showThumbnail: true`.
    @Test func testOldPreviewAndRingKeysDecodeToNewDefaults() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        var preview = object["preview"] as! [String: Any]
        preview["previewStyle"] = nil
        preview["outlineCurrent"] = nil
        preview["showThumbnail"] = true
        object["preview"] = preview
        var ring = object["ring"] as! [String: Any]
        for key in ["boundary", "columnNumbers", "pointingHint"] { ring[key] = nil }
        object["ring"] = ring
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: data)
        #expect(decoded.preview.style == .tint)
        #expect(!decoded.preview.showCurrentOutline)
        #expect(!decoded.ring.showBoundary && decoded.ring.showColumnNumbers && decoded.ring.showPointingHint)
        try SettingsValidation.validate(decoded)
    }

    @Test func testStyleRoundTrips() throws {
        for style in PreviewStyle.allCases {
            var s = TesseraSettings.defaults
            s.preview.style = style
            s.ring.showBoundary = true
            let back = try JSONDecoder().decode(TesseraSettings.self, from: JSONEncoder().encode(s))
            #expect(back.preview.style == style && back.ring.showBoundary)
        }
    }

    @Test func testPointingHintStopsAfterLimit() {
        var ring = RingSettings()
        #expect(ring.pointingHintDue)
        ring.pointingHintsSeen = PreviewModel.hintSessions - 1
        #expect(ring.pointingHintDue)
        ring.pointingHintsSeen = PreviewModel.hintSessions
        #expect(!ring.pointingHintDue)
        ring.pointingHintsSeen = nil
        ring.showPointingHint = false
        #expect(!ring.pointingHintDue)
    }
}
