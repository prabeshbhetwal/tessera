import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

@Suite struct SnapSpeedTests {
    @Test func testPresetsRoundTripThroughSeconds() {
        for speed in SnapSpeed.allCases {
            #expect(SnapSpeed(seconds: speed.seconds) == speed)
        }
        #expect(SnapSpeed(seconds: 0.27) == nil)
    }

    @Test func testDefaultIsInstantAndClamped() {
        var s = TesseraSettings.defaults
        #expect(s.snapSeconds == 0)
        s.snapDuration = 5
        #expect(s.snapSeconds == SnapSpeed.maxSeconds)
        s.snapDuration = -1
        #expect(s.snapSeconds == 0)
        s.snapDuration = .nan
        #expect(s.snapSeconds == 0)
        s.snapSeconds = 0.3
        #expect(s.snapDuration == 0.3)
    }

    /// A v2 file written before snap speed existed must still load, not be quarantined.
    @Test func testSettingsWithoutSnapDurationDecode() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        object["snapDuration"] = nil
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: data)
        #expect(decoded.snapDuration == nil)
        try SettingsValidation.validate(decoded)
    }

    @Test func testValidationRejectsOutOfRangeDuration() {
        var s = TesseraSettings.defaults
        s.snapDuration = 1.5
        #expect(throws: SettingsError.self) { try SettingsValidation.validate(s) }
        s.snapDuration = .nan
        #expect(throws: SettingsError.self) { try SettingsValidation.validate(s) }
        s.snapDuration = SnapSpeed.relaxed.seconds
        #expect(throws: Never.self) { try SettingsValidation.validate(s) }
    }

    /// Once pointing, the cursor must come `pointHysteresis` back inside before a wedge is picked again.
    @Test func testPointingHysteresis() {
        let display = DisplayContext(
            id: DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 1047),
            range: ColumnRange(minCols: 3, maxCols: 6, defaultCols: 5, maxRows: 2, isPortrait: false),
            profile: DisplayProfile(columns: 5, gap: 8, padding: 8))
        let engine = SelectionEngine(ring: RingSettings())
        let origin = CGPoint(x: 500, y: 500)
        let near = CGPoint(x: origin.x + 86, y: origin.y) // inside 90, within the 8 pt band
        let inside = CGPoint(x: origin.x + 80, y: origin.y)

        #expect(engine.select(origin: origin, cursor: near, displays: [display], anchor: nil, pointing: false)
            == .wedge(index: 2, action: .rightHalf))
        if case .span = engine.select(origin: origin, cursor: near, displays: [display], anchor: nil, pointing: true) {} else {
            Issue.record("expected to keep pointing inside the hysteresis band")
        }
        #expect(engine.select(origin: origin, cursor: inside, displays: [display], anchor: nil, pointing: true)
            == .wedge(index: 2, action: .rightHalf))
    }
}
