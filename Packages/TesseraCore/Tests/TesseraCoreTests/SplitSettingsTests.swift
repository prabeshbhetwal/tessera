import Foundation
import Testing
@testable import TesseraCore

@Suite struct SplitSettingsTests {
    private static let splitKeys = [
        "learnSplits", "splitRestoresOrder", "splitGapPlacement", "splitGapWhenGrowing", "learnedSplits",
    ]

    private func split(
        apps: [String] = ["com.a", "com.b"],
        slots: [Slot]? = nil,
        updated: Date = Date(timeIntervalSinceReferenceDate: 1000)
    ) -> LearnedSplit {
        LearnedSplit(
            key: SplitKey(display: "d", bundleIDs: apps),
            slots: slots ?? [
                Slot(bundleID: "com.a", rect: UnitRect(x: 0, y: 0, width: 0.5, height: 1)),
                Slot(bundleID: "com.b", rect: UnitRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            ],
            updated: updated
        )
    }

    private func settings(withSlotRect rect: UnitRect) -> TesseraSettings {
        var s = TesseraSettings.defaults
        s.learnedSplits = [split(slots: [Slot(bundleID: "com.a", rect: rect)])]
        return s
    }

    @Test func defaults() {
        let s = TesseraSettings.defaults
        #expect(s.learnSplits)
        #expect(!s.splitRestoresOrder)
        #expect(s.splitGapPlacement == .staysInPlace)
        #expect(s.splitGapWhenGrowing == .fixed)
        #expect(s.learnedSplits.isEmpty)
    }

    /// A v2 file written before learned splits existed must load with defaults, not be quarantined.
    @Test func oldFileGainsSplitKeys() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        for key in Self.splitKeys { object[key] = nil }
        let migrated = try SettingsMigration.migrate(JSONSerialization.data(withJSONObject: object))
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: migrated.data)
        #expect(decoded == TesseraSettings.defaults)
        #expect(throws: Never.self) { try SettingsValidation.validate(decoded) }
    }

    @Test func roundTripsLearnedSplit() throws {
        var s = TesseraSettings.defaults
        s.learnedSplits = [split()]
        s.splitGapPlacement = .followsNeighbour
        s.splitGapWhenGrowing = .shrinks
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func validationRejectsBadRects() {
        let bad = [
            UnitRect(x: 0, y: 0, width: .nan, height: 1),
            UnitRect(x: 0, y: .infinity, width: 0.5, height: 1),
            UnitRect(x: 0.6, y: 0, width: 0.5, height: 1),
            UnitRect(x: 0, y: 0.6, width: 0.5, height: 0.5),
            UnitRect(x: 0, y: 0, width: 0, height: 1),
            UnitRect(x: 0, y: 0, width: 0.5, height: -0.1),
            UnitRect(x: -0.1, y: 0, width: 0.5, height: 1),
            UnitRect(x: 0, y: -0.1, width: 0.5, height: 1),
        ]
        for rect in bad {
            #expect(throws: SettingsError.invalid("A learned split has an invalid size."), "\(rect)") {
                try SettingsValidation.validate(settings(withSlotRect: rect))
            }
        }
        // Float rounding at the far edge is tolerated.
        #expect(throws: Never.self) {
            try SettingsValidation.validate(settings(withSlotRect: UnitRect(x: 0.5, y: 0, width: 0.5000001, height: 1)))
        }
    }

    @Test func validationRejectsOverCap() {
        var s = TesseraSettings.defaults
        s.learnedSplits = (0..<SplitMemory.capacity).map { split(apps: ["com.a", "app\($0)"]) }
        #expect(throws: Never.self) { try SettingsValidation.validate(s) }
        s.learnedSplits.append(split(apps: ["com.a", "extra"]))
        #expect(throws: SettingsError.invalid("Too many learned splits (at most 50).")) {
            try SettingsValidation.validate(s)
        }
    }

    /// The applier returns nil for a mismatched split at Tile time; rejecting here would quarantine the
    /// user's whole settings file.
    @Test func validationAllowsMismatchedApps() {
        var s = TesseraSettings.defaults
        s.learnedSplits = [split(apps: ["com.x", "com.y"])]
        #expect(throws: Never.self) { try SettingsValidation.validate(s) }
    }
}
