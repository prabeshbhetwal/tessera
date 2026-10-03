import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct SizingRuleTests {
    /// One row of spec §3.4. For portrait rows the "cols" fields mean rows.
    struct Fixture: Sendable, CustomTestStringConvertible {
        let name: String
        let width: Double
        let height: Double
        let minCols: Int
        let maxCols: Int
        let defaultCols: Int
        /// nil for portrait (spec says n/a).
        let maxRows: Int?
        var testDescription: String { name }
    }

    static let fixtures: [Fixture] = [
        .init(name: "MacBook Air 13",  width: 1470, height: 923,  minCols: 2, maxCols: 2, defaultCols: 2, maxRows: 2),
        .init(name: "MacBook Pro 14",  width: 1512, height: 949,  minCols: 2, maxCols: 2, defaultCols: 2, maxRows: 2),
        .init(name: "MacBook Pro 16",  width: 1728, height: 1084, minCols: 2, maxCols: 2, defaultCols: 2, maxRows: 2),
        .init(name: "24in 1080p",      width: 1920, height: 1047, minCols: 2, maxCols: 3, defaultCols: 2, maxRows: 2),
        .init(name: "27in 1440p/5K",   width: 2560, height: 1407, minCols: 2, maxCols: 4, defaultCols: 3, maxRows: 3),
        .init(name: "34in ultrawide",  width: 3440, height: 1407, minCols: 3, maxCols: 5, defaultCols: 4, maxRows: 3),
        .init(name: "CHG90 49in",      width: 3840, height: 1047, minCols: 3, maxCols: 6, defaultCols: 5, maxRows: 2),
        .init(name: "57in dual-4K",    width: 7680, height: 2127, minCols: 6, maxCols: 8, defaultCols: 8, maxRows: 4),
        .init(name: "27in portrait",   width: 1440, height: 2527, minCols: 2, maxCols: 3, defaultCols: 3, maxRows: nil),
    ]

    @Test(arguments: fixtures)
    func specFixtures(_ f: Fixture) {
        let r = SizingRule.range(for: CGSize(width: f.width, height: f.height), constants: .default)
        #expect(r.minCols == f.minCols)
        #expect(r.maxCols == f.maxCols)
        #expect(r.defaultCols == f.defaultCols)
        if let rows = f.maxRows { #expect(r.maxRows == rows) }
        #expect(r.isPortrait == (f.height > f.width))
    }

    @Test func zeroOrTinySizeYieldsOneColumn() {
        for size in [CGSize(width: 300, height: 200), .zero, CGSize(width: -5, height: CGFloat.nan)] {
            let r = SizingRule.range(for: size, constants: .default)
            #expect(r.minCols == 1 && r.maxCols == 1 && r.defaultCols == 1)
            #expect(r.maxRows >= 1)
        }
    }

    @Test func degenerateConstantsNeverBreakInvariants() {
        var c = SizingConstants.default
        c.maxColumns = 1            // below minCols for a wide display
        c.minColumnWidth = 0        // would divide by zero
        let r = SizingRule.range(for: CGSize(width: 3840, height: 1047), constants: c)
        #expect(r.minCols >= 1)
        #expect(r.maxCols >= r.minCols)
        #expect((r.minCols...r.maxCols).contains(r.defaultCols))
    }

    @Test func clampOutOfRange() {
        let chg90 = SizingRule.range(for: CGSize(width: 3840, height: 1047), constants: .default)
        #expect(DisplayProfile(columns: 9).clamped(to: chg90).columns == 6)
        #expect(DisplayProfile(columns: 0).clamped(to: chg90).columns == 3)
        #expect(DisplayProfile(columns: -4).clamped(to: chg90).columns == 3)
        #expect(DisplayProfile(columns: 4).clamped(to: chg90).columns == 4)
    }

    @Test func clampKeepsOtherFields() {
        let range = ColumnRange(minCols: 2, maxCols: 3, defaultCols: 2, maxRows: 2, isPortrait: false)
        let p = DisplayProfile(columns: 9, gap: 12, padding: 3, isUserOverride: true).clamped(to: range)
        #expect(p == DisplayProfile(columns: 3, gap: 12, padding: 3, isUserOverride: true))
    }

    @Test func autoProfileUsesDefaultColumns() {
        let chg90 = SizingRule.range(for: CGSize(width: 3840, height: 1047), constants: .default)
        let p = DisplayProfile.auto(range: chg90, gap: 6, padding: 10)
        #expect(p == DisplayProfile(columns: 5, gap: 6, padding: 10, isUserOverride: false))
    }

    @Test func clampNeverYieldsZeroColumnsEvenForBogusRange() {
        let bogus = ColumnRange(minCols: 0, maxCols: 0, defaultCols: 0, maxRows: 0, isPortrait: false)
        #expect(DisplayProfile(columns: 0).clamped(to: bogus).columns >= 1)
    }
}
