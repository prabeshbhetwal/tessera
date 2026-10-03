import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct GridGeometryTests {
    static let id = DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil)

    static func context(_ visible: CGRect, columns: Int? = nil, gap: Double = 8, padding: Double = 8) -> DisplayContext {
        let usable = visible.insetBy(dx: padding, dy: padding)
        let range = SizingRule.range(for: usable.size, constants: .default)
        let profile = DisplayProfile(columns: columns ?? range.defaultCols, gap: gap, padding: padding)
        return DisplayContext(id: id, visibleFrame: visible, range: range, profile: profile)
    }

    static let chg90 = context(CGRect(x: 0, y: 0, width: 3840, height: 1047))      // 5 columns
    static let macbook = context(CGRect(x: 0, y: 0, width: 1512, height: 949))     // 2 columns

    static func expectEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.01,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a.minX - b.minX) <= tolerance, "x \(a.minX) vs \(b.minX)", sourceLocation: sourceLocation)
        #expect(abs(a.minY - b.minY) <= tolerance, "y \(a.minY) vs \(b.minY)", sourceLocation: sourceLocation)
        #expect(abs(a.width - b.width) <= tolerance, "w \(a.width) vs \(b.width)", sourceLocation: sourceLocation)
        #expect(abs(a.height - b.height) <= tolerance, "h \(a.height) vs \(b.height)", sourceLocation: sourceLocation)
    }

    // MARK: usableFrame

    @Test func usableFrameInsetsByPadding() {
        let u = GridGeometry.usableFrame(CGRect(x: 0, y: 0, width: 3840, height: 1047), profile: DisplayProfile(columns: 5, padding: 8))
        #expect(u == CGRect(x: 8, y: 8, width: 3824, height: 1031))
    }

    @Test func hugePaddingNeverProducesNegativeFrame() {
        let u = GridGeometry.usableFrame(CGRect(x: 0, y: 0, width: 100, height: 50), profile: DisplayProfile(columns: 1, padding: 500))
        #expect(u.width >= 0 && u.height >= 0 && !u.isNull && !u.isInfinite)
    }

    // MARK: spans

    @Test func fiveColumnsCHG90() {
        let f = GridGeometry.frame(for: ColumnSpan(columns: 1...1, band: .full), display: Self.chg90)
        let colW = 3824.0 / 5            // 764.8
        #expect(abs(f.minX - (8 + colW + 4)) < 0.01)
        #expect(abs(f.width - (colW - 8)) < 0.01)
        // Full band: touches top and bottom of the usable frame, so no vertical gap.
        #expect(abs(f.minY - 8) < 0.01 && abs(f.height - 1031) < 0.01)
    }

    @Test func firstAndLastColumnsOnlyInsetInnerEdge() {
        let first = GridGeometry.frame(for: ColumnSpan(columns: 0...0, band: .full), display: Self.chg90)
        #expect(abs(first.minX - 8) < 0.01 && abs(first.width - (764.8 - 4)) < 0.01)
        let last = GridGeometry.frame(for: ColumnSpan(columns: 4...4, band: .full), display: Self.chg90)
        #expect(abs(last.maxX - (8 + 3824)) < 0.01 && abs(last.width - (764.8 - 4)) < 0.01)
    }

    @Test func adjacentSpansAreExactlyOneGapApart() {
        let a = GridGeometry.frame(for: ColumnSpan(columns: 0...1, band: .full), display: Self.chg90)
        let b = GridGeometry.frame(for: ColumnSpan(columns: 2...4, band: .full), display: Self.chg90)
        #expect(abs((b.minX - a.maxX) - 8) < 0.01)
    }

    @Test func spanUnion() {
        let one = GridGeometry.frame(for: ColumnSpan(columns: 1...1, band: .full), display: Self.chg90)
        let three = GridGeometry.frame(for: ColumnSpan(columns: 3...3, band: .full), display: Self.chg90)
        let union = GridGeometry.frame(for: ColumnSpan(columns: 1...3, band: .full), display: Self.chg90)
        #expect(abs(union.minX - one.minX) < 0.01)
        #expect(abs(union.maxX - three.maxX) < 0.01)
        // One continuous frame: width = 3 columns minus the two outer half-gaps.
        #expect(abs(union.width - (3 * 764.8 - 8)) < 0.01)
    }

    @Test func topBand() {
        let f = GridGeometry.frame(for: ColumnSpan(columns: 0...0, band: .top), display: Self.chg90)
        let usableH = 1031.0
        #expect(abs(f.height - (usableH / 2 - 4)) < 0.01)
        #expect(abs(f.maxY - (8 + usableH)) < 0.01)      // flush with the top of usable (higher y in AppKit)
        let b = GridGeometry.frame(for: ColumnSpan(columns: 0...0, band: .bottom), display: Self.chg90)
        #expect(abs(b.minY - 8) < 0.01 && abs(b.height - (usableH / 2 - 4)) < 0.01)
        #expect(abs((f.minY - b.maxY) - 8) < 0.01)       // exactly one gap between the bands
    }

    @Test func spanIsClampedToColumnCount() {
        let f = GridGeometry.frame(for: ColumnSpan(columns: 3...99, band: .full), display: Self.chg90)
        #expect(abs(f.maxX - 3832) < 0.01)
        let g = GridGeometry.frame(for: ColumnSpan(columns: 99...120, band: .full), display: Self.chg90)
        #expect(abs(g.maxX - 3832) < 0.01 && g.width > 0)
    }

    @Test func offsetDisplayKeepsGlobalOrigin() {
        // Display to the left of the primary: negative x, non-zero y.
        let d = Self.context(CGRect(x: -2560, y: 100, width: 2560, height: 1407), columns: 2)
        let f = GridGeometry.frame(for: ColumnSpan(columns: 0...0, band: .full), display: d)
        #expect(abs(f.minX - (-2560 + 8)) < 0.01 && abs(f.minY - 108) < 0.01)
    }

    @Test func portraitRows() {
        // 27" portrait: 3 rows, indexed from the top, full width, band ignored.
        let d = Self.context(CGRect(x: -1440, y: 0, width: 1440, height: 2543), columns: 3)
        #expect(d.range.isPortrait)
        let usable = CGRect(x: -1432, y: 8, width: 1424, height: 2527)
        let rowH = 2527.0 / 3
        let top = GridGeometry.frame(for: ColumnSpan(columns: 0...0, band: .bottom), display: d)
        Self.expectEqual(top, CGRect(x: usable.minX, y: usable.maxY - rowH + 4, width: usable.width, height: rowH - 4))
        let last = GridGeometry.frame(for: ColumnSpan(columns: 2...2, band: .top), display: d)
        Self.expectEqual(last, CGRect(x: usable.minX, y: usable.minY, width: usable.width, height: rowH - 4))
        let both = GridGeometry.frame(for: ColumnSpan(columns: 0...1, band: .full), display: d)
        Self.expectEqual(both, CGRect(x: usable.minX, y: usable.maxY - 2 * rowH + 4, width: usable.width, height: 2 * rowH - 4))
    }

    // MARK: actions

    @Test func leftHalfMacBook() {
        let f = GridGeometry.frame(for: .leftHalf, display: Self.macbook, current: .zero)
        // usable = (8, 8, 1496, 933); right edge inset by gap/2.
        Self.expectEqual(f, CGRect(x: 8, y: 8, width: 748 - 4, height: 933))
        let r = GridGeometry.frame(for: .rightHalf, display: Self.macbook, current: .zero)
        Self.expectEqual(r, CGRect(x: 8 + 748 + 4, y: 8, width: 748 - 4, height: 933))
        #expect(abs((r.minX - f.maxX) - 8) < 0.01)
    }

    @Test func maximizeFillsUsableWithoutGaps() {
        let f = GridGeometry.frame(for: .maximize, display: Self.macbook, current: .zero)
        Self.expectEqual(f, CGRect(x: 8, y: 8, width: 1496, height: 933))
    }

    @Test func halvesTopAndBottom() {
        let t = GridGeometry.frame(for: .topHalf, display: Self.macbook, current: .zero)
        Self.expectEqual(t, CGRect(x: 8, y: 8 + 466.5 + 4, width: 1496, height: 466.5 - 4))
        let b = GridGeometry.frame(for: .bottomHalf, display: Self.macbook, current: .zero)
        Self.expectEqual(b, CGRect(x: 8, y: 8, width: 1496, height: 466.5 - 4))
    }

    @Test(arguments: [
        (WindowAction.topLeftQuarter, 0.0, 1.0),
        (.topRightQuarter, 1.0, 1.0),
        (.bottomLeftQuarter, 0.0, 0.0),
        (.bottomRightQuarter, 1.0, 0.0),
    ])
    func quarter(_ action: WindowAction, _ right: Double, _ top: Double) {
        let f = GridGeometry.frame(for: action, display: Self.macbook, current: .zero)
        let x = 8 + right * (748 + 4)
        let y = 8 + top * (466.5 + 4)
        Self.expectEqual(f, CGRect(x: x, y: y, width: 748 - 4, height: 466.5 - 4))
    }

    @Test func centerKeepsSizeAndClamps() {
        let current = CGRect(x: 40, y: 60, width: 1000, height: 700)
        let c = GridGeometry.frame(for: .center, display: Self.macbook, current: current)
        Self.expectEqual(c, CGRect(x: 8 + 248, y: 8 + 116.5, width: 1000, height: 700))   // no gaps

        let big = GridGeometry.frame(for: .center, display: Self.macbook,
                                     current: CGRect(x: 0, y: 0, width: 5000, height: 4000))
        Self.expectEqual(big, CGRect(x: 8, y: 8, width: 1496, height: 933))
    }

    @Test(arguments: WindowAction.allCases)
    func everyActionStaysInsideUsable(_ action: WindowAction) {
        let usable = CGRect(x: 8, y: 8, width: 1496, height: 933)
        let f = GridGeometry.frame(for: action, display: Self.macbook, current: CGRect(x: 0, y: 0, width: 600, height: 400))
        #expect(usable.insetBy(dx: -0.001, dy: -0.001).contains(f))
        #expect(f.width > 0 && f.height > 0)
    }

    // MARK: columnIndex

    @Test func columnIndexMapsCHG90Fixture() {
        let usable = CGRect(x: 0, y: 0, width: 3840, height: 1047)
        #expect(GridGeometry.columnIndex(at: 1600, in: usable, columns: 5) == 2)   // shared with input-logic
        #expect(GridGeometry.columnIndex(at: 0, in: usable, columns: 5) == 0)
        #expect(GridGeometry.columnIndex(at: 767.99, in: usable, columns: 5) == 0)
        #expect(GridGeometry.columnIndex(at: 768, in: usable, columns: 5) == 1)
    }

    @Test func columnIndexClamps() {
        let usable = CGRect(x: 8, y: 8, width: 3824, height: 1031)
        #expect(GridGeometry.columnIndex(at: -500, in: usable, columns: 5) == 0)
        #expect(GridGeometry.columnIndex(at: 4000, in: usable, columns: 5) == 4)
        #expect(GridGeometry.columnIndex(at: usable.maxX, in: usable, columns: 5) == 4)
        #expect(GridGeometry.columnIndex(at: 100, in: usable, columns: 0) == 0)
        #expect(GridGeometry.columnIndex(at: .nan, in: usable, columns: 5) == 0)
    }

    @Test func portraitIndexCountsRowsFromTop() {
        let usable = CGRect(x: 0, y: 0, width: 1440, height: 3000)
        // y up: near the top of the frame is row 0, near the bottom is the last row.
        #expect(GridGeometry.index(at: CGPoint(x: 10, y: 2990), in: usable, count: 3, portrait: true) == 0)
        #expect(GridGeometry.index(at: CGPoint(x: 10, y: 1500), in: usable, count: 3, portrait: true) == 1)
        #expect(GridGeometry.index(at: CGPoint(x: 10, y: 5), in: usable, count: 3, portrait: true) == 2)
        #expect(GridGeometry.index(at: CGPoint(x: 10, y: -50), in: usable, count: 3, portrait: true) == 2)
        #expect(GridGeometry.index(at: CGPoint(x: 1000, y: 5), in: usable, count: 3, portrait: false) == 2)
    }
}
