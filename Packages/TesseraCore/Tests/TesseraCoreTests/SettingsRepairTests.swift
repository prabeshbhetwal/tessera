import Foundation
import Testing
@testable import TesseraCore

@Suite struct SettingsRepairTests {
    private func repaired(_ mutate: (inout TesseraSettings) -> Void) -> (settings: TesseraSettings, repairs: [String]) {
        var s = TesseraSettings.defaults
        mutate(&s)
        return SettingsValidation.repair(s)
    }

    @Test func validSettingsComeBackUnchanged() {
        var s = TesseraSettings.defaults
        s.ring.pointing = false
        s.ring.radius = 140
        s.defaultGap = 40
        s.displayOverrides["x"] = DisplayProfile(columns: 16, gap: 0, padding: 40, isUserOverride: true)
        for settings in [TesseraSettings.defaults, s] {
            let result = SettingsValidation.repair(settings)
            #expect(result.settings == settings)
            #expect(result.repairs.isEmpty)
        }
    }

    /// Every case `validate` rejects (other than the schema version) comes out valid.
    @Test func everyRepairedCasePassesValidation() throws {
        let cases: [(inout TesseraSettings) -> Void] = [
            { $0.ring.wedges.removeLast() },
            { $0.sizing.minColumnWidth = 0 },
            { $0.sizing.minColumnWidth = 900 },
            { $0.sizing.maxColumnWidth = .infinity },
            { $0.sizing.minRowHeight = .nan },
            { $0.sizing.maxColumns = 40 },
            { $0.defaultGap = .nan },
            { $0.defaultPadding = -3 },
            { $0.ring.deadZone = 90 },
            { $0.ring.flickDistance = -1 },
            { $0.ring.topBand = 0.7; $0.ring.bottomBand = 0.7 },
            { $0.ring.radius = 120 },
            { $0.preview.opacity = 4 },
            { $0.preview.springResponse = -1 },
            { $0.hudSeconds = 0 },
            { $0.snapDuration = 99 },
            { $0.displayOverrides["x"] = DisplayProfile(columns: 0, gap: 90, padding: .nan) },
            { $0.customThemes = [Theme(name: "", ring: Theme.default.ring, preview: .default, accentHex: "#FFFFFF")] },
            { $0.hotkeys.append($0.hotkeys[0]) },
            { $0.trigger = TriggerChord(keyCodes: []) },
        ]
        for (i, mutate) in cases.enumerated() {
            let result = repaired(mutate)
            #expect(throws: Never.self, "case \(i)") { try SettingsValidation.validate(result.settings) }
            #expect(!result.repairs.isEmpty || i == 8, "case \(i) should say what it changed")
        }
    }

    @Test func clampsToTheNearestEndAndResetsNonFiniteValues() {
        let result = repaired { s in
            s.defaultGap = 100
            s.defaultPadding = .nan
            s.displayOverrides["x"] = DisplayProfile(columns: 30, isUserOverride: true)
        }
        #expect(result.settings.defaultGap == 40)
        #expect(result.settings.defaultPadding == TesseraSettings.defaults.defaultPadding)
        #expect(result.settings.displayOverrides["x"]?.columns == 16)
        #expect(result.repairs.first == "The default gap was 100 and is now 40.")
    }

    @Test func sortsColumnWidthsRatherThanDiscardingThem() {
        let result = repaired { s in
            s.sizing.minColumnWidth = 900
            s.sizing.idealColumnWidth = 700
            s.sizing.maxColumnWidth = 800
        }
        let sizing = result.settings.sizing
        #expect([sizing.minColumnWidth, sizing.idealColumnWidth, sizing.maxColumnWidth] == [700, 800, 900])
    }

    @Test func raisesThePointThresholdOutsideTheRing() {
        let result = repaired { $0.ring.radius = 120 }
        #expect(result.settings.ring.flickDistance == 131)
        #expect(SettingsValidation.directionsReachable(result.settings.ring))
    }

    @Test func deadZoneIsFixedQuietly() {
        let result = repaired { $0.ring.deadZone = 500 }
        #expect(result.settings.ring.deadZone == RingSettings.default.deadZone)
        #expect(result.repairs.isEmpty, "the dead zone no longer does anything the person can see")
    }

    @Test func keepsTheFirstHotkeyOfEachId() {
        var second = HotkeyBinding.defaults[0]
        second.enabled = false
        let result = repaired { $0.hotkeys.append(second) }
        #expect(result.settings.hotkeys == HotkeyBinding.defaults)
    }

    @Test func dropsOnlyBadOrExcessLearnedSplits() {
        func split(_ n: Int, width: Double = 1) -> LearnedSplit {
            LearnedSplit(key: SplitKey(display: "d", bundleIDs: ["app\(n)"]),
                         slots: [Slot(bundleID: "app\(n)", rect: UnitRect(x: 0, y: 0, width: width, height: 1))],
                         updated: Date(timeIntervalSince1970: Double(n)))
        }
        let good = (0...SplitMemory.capacity).map { split($0) }
        let result = repaired { $0.learnedSplits = [split(-1, width: .nan)] + good }
        #expect(result.settings.learnedSplits == Array(good.dropFirst()), "the bad one and the oldest go")
        #expect(result.repairs.count == 2)
    }

    // MARK: Validation bounds reachable through Import

    @Test func validationRejectsTheNewBounds() {
        let cases: [(String, (inout TesseraSettings) -> Void)] = [
            ("gap 41", { $0.defaultGap = 41 }),
            ("padding 41", { $0.defaultPadding = 41 }),
            ("override columns 17", { $0.displayOverrides["x"] = DisplayProfile(columns: 17) }),
            ("override gap 41", { $0.displayOverrides["x"] = DisplayProfile(columns: 2, gap: 41) }),
            ("ring past the point threshold", { $0.ring.radius = 85 }),
        ]
        for (name, mutate) in cases {
            var s = TesseraSettings.defaults
            mutate(&s)
            #expect(throws: SettingsError.self, "\(name) should be rejected") { try SettingsValidation.validate(s) }
        }
    }

    @Test func ringPastThePointThresholdIsFineWithPointingOff() {
        var s = TesseraSettings.defaults
        s.ring.radius = 85
        s.ring.pointing = false
        #expect(throws: Never.self) { try SettingsValidation.validate(s) }
        // The Ring pane lets the ring's outer edge sit exactly on the threshold.
        s.ring.pointing = true
        s.ring.radius = s.ring.flickDistance - s.ring.thickness / 2
        #expect(throws: Never.self) { try SettingsValidation.validate(s) }
    }
}
