import CoreGraphics
import Testing

@testable import TesseraCore

private let chgID = DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil)
private let sideID = DisplayID(vendor: 4, model: 5, serial: 6, uuid: nil)

/// CHG90 fixture: 3840x1047 visible frame, padding 8, 5 columns, at the origin.
private func chg(columns: Int = 5, origin: CGPoint = .zero) -> DisplayContext {
    DisplayContext(
        id: chgID,
        visibleFrame: CGRect(x: origin.x, y: origin.y, width: 3840, height: 1047),
        range: ColumnRange(minCols: 3, maxCols: 6, defaultCols: 5, maxRows: 2, isPortrait: false),
        profile: DisplayProfile(columns: columns, gap: 8, padding: 8))
}

/// MacBook-ish display placed to the right of the CHG90 (x 3840...5352).
private func side() -> DisplayContext {
    DisplayContext(
        id: sideID,
        visibleFrame: CGRect(x: 3840, y: 0, width: 1512, height: 949),
        range: ColumnRange(minCols: 2, maxCols: 2, defaultCols: 2, maxRows: 2, isPortrait: false),
        profile: DisplayProfile(columns: 2, gap: 8, padding: 8))
}

private func portrait() -> DisplayContext {
    DisplayContext(
        id: sideID,
        visibleFrame: CGRect(x: -1440, y: 0, width: 1440, height: 2527),
        range: ColumnRange(minCols: 2, maxCols: 3, defaultCols: 3, maxRows: 2, isPortrait: true),
        profile: DisplayProfile(columns: 3, gap: 8, padding: 8))
}

private let engine = SelectionEngine(ring: RingSettings())
private let origin = CGPoint(x: 500, y: 500)

/// Cursor at `distance` from `origin`, `degrees` clockwise from up (AppKit, y up).
private func cursor(at degrees: Double, distance: Double = 50) -> CGPoint {
    let rad = degrees * .pi / 180
    return CGPoint(x: origin.x + distance * sin(rad), y: origin.y + distance * cos(rad))
}

@Suite struct SelectionEngineTests {
    @Test func testDeadZone() {
        let c = CGPoint(x: origin.x + 9.99, y: origin.y)
        #expect(engine.select(origin: origin, cursor: c, displays: [chg()], anchor: nil) == .none)
        #expect(engine.select(origin: origin, cursor: origin, displays: [chg()], anchor: nil) == .none)
    }

    @Test func testFlickBoundaries() {
        let d = [chg()]
        let at10 = CGPoint(x: origin.x + 10, y: origin.y)
        let at8999 = CGPoint(x: origin.x + 89.99, y: origin.y)
        let at90 = CGPoint(x: origin.x + 90, y: origin.y)
        #expect(engine.select(origin: origin, cursor: at10, displays: d, anchor: nil)
            == .wedge(index: 2, action: .rightHalf))
        #expect(engine.select(origin: origin, cursor: at8999, displays: d, anchor: nil)
            == .wedge(index: 2, action: .rightHalf))
        if case .span = engine.select(origin: origin, cursor: at90, displays: d, anchor: nil) {
        } else {
            Issue.record("d == 90 must be point mode")
        }
    }

    @Test(arguments: [
        (0.0, 0), (22.49, 0), (22.5, 1), (90.0, 2), (180.0, 4), (270.0, 6), (337.5, 0),
    ])
    func testWedgeAngles(degrees: Double, index: Int) {
        let sel = engine.select(
            origin: origin, cursor: cursor(at: degrees), displays: [chg()], anchor: nil)
        #expect(sel == .wedge(index: index, action: RingSettings().wedges[index]))
    }

    @Test func testWedgeIndexZeroIsMaximize() {
        let sel = engine.select(
            origin: origin, cursor: cursor(at: 0), displays: [chg()], anchor: nil)
        #expect(sel == .wedge(index: 0, action: .maximize))
    }

    @Test func testPointCHG90Column() {
        let c = CGPoint(x: 1600, y: 500)
        let sel = engine.select(origin: .zero, cursor: c, displays: [chg()], anchor: nil)
        #expect(sel == .span(display: chgID, span: ColumnSpan(columns: 2...2, band: .full)))
    }

    @Test func testColumnClampsAtEdges() {
        // Inside visibleFrame but within the padding strip: clamps to first/last column.
        let left = engine.select(
            origin: .zero, cursor: CGPoint(x: 2, y: 500), displays: [chg()], anchor: nil)
        let right = engine.select(
            origin: .zero, cursor: CGPoint(x: 3838, y: 500), displays: [chg()], anchor: nil)
        #expect(left == .span(display: chgID, span: ColumnSpan(columns: 0...0, band: .full)))
        #expect(right == .span(display: chgID, span: ColumnSpan(columns: 4...4, band: .full)))
    }

    @Test func testBands() {
        func band(atFraction f: Double) -> Band? {
            let c = CGPoint(x: 1600, y: 1047 * f)
            guard case .span(_, let span) = engine.select(
                origin: .zero, cursor: c, displays: [chg()], anchor: nil)
            else { return nil }
            return span.band
        }
        #expect(band(atFraction: 0.8) == .top)
        #expect(band(atFraction: 0.5) == .full)
        #expect(band(atFraction: 0.2) == .bottom)
    }

    @Test func testAnchorSpan() {
        let d = [chg()]
        let anchor = SpanAnchor(display: chgID, column: 1, band: .top)
        // x for column 3: 8 + 3.5 * 764.8 = 2684.8
        let topCursor = CGPoint(x: 2684.8, y: 1047 * 0.8)
        let fullCursor = CGPoint(x: 2684.8, y: 1047 * 0.5)
        #expect(engine.select(origin: .zero, cursor: topCursor, displays: d, anchor: anchor)
            == .span(display: chgID, span: ColumnSpan(columns: 1...3, band: .top)))
        #expect(engine.select(origin: .zero, cursor: fullCursor, displays: d, anchor: anchor)
            == .span(display: chgID, span: ColumnSpan(columns: 1...3, band: .full)))
    }

    @Test func testAnchorRightOfCursorOrdersColumns() {
        let anchor = SpanAnchor(display: chgID, column: 4, band: .full)
        let sel = engine.select(
            origin: .zero, cursor: CGPoint(x: 1600, y: 500), displays: [chg()], anchor: anchor)
        #expect(sel == .span(display: chgID, span: ColumnSpan(columns: 2...4, band: .full)))
    }

    @Test func testAnchorBeyondColumnCountIsClamped() {
        // Columns reduced (scroll) after anchoring: stale anchor column must not escape range.
        let anchor = SpanAnchor(display: chgID, column: 7, band: .full)
        let sel = engine.select(
            origin: .zero, cursor: CGPoint(x: 100, y: 500), displays: [chg(columns: 3)],
            anchor: anchor)
        #expect(sel == .span(display: chgID, span: ColumnSpan(columns: 0...2, band: .full)))
    }

    // Review Focus 1
    @Test func testCursorOutsideDisplays() {
        let d = [chg()]
        let outside = [
            CGPoint(x: -5, y: 500), CGPoint(x: 5000, y: 500),
            CGPoint(x: 1600, y: 5000), CGPoint(x: 1600, y: -1),
            CGPoint(x: 3840, y: 500),  // right edge is exclusive
        ]
        for c in outside {
            #expect(engine.select(origin: .zero, cursor: c, displays: d, anchor: nil) == .none)
        }
        #expect(engine.select(origin: .zero, cursor: CGPoint(x: 1600, y: 500), displays: [], anchor: nil) == .none)
    }

    // Review Focus 1: gap between two displays.
    @Test func testCursorInGapBetweenDisplays() {
        let left = chg()
        let right = DisplayContext(
            id: sideID,
            visibleFrame: CGRect(x: 3940, y: 0, width: 1512, height: 949),  // 100pt gap
            range: side().range, profile: side().profile)
        let inGap = CGPoint(x: 3890, y: 500)
        #expect(
            engine.select(origin: .zero, cursor: inGap, displays: [left, right], anchor: nil)
                == .none)
        #expect(engine.anchor(at: inGap, displays: [left, right]) == nil)
    }

    @Test func testPickedDisplayFollowsCursor() {
        let c = CGPoint(x: 3840 + 1000, y: 500)  // right half of the second display
        let sel = engine.select(origin: .zero, cursor: c, displays: [chg(), side()], anchor: nil)
        #expect(sel == .span(display: sideID, span: ColumnSpan(columns: 1...1, band: .full)))
    }

    // Review Focus 5
    @Test func testAnchorOnOtherDisplayIgnored() {
        let displays = [chg(), side()]
        let anchor = SpanAnchor(display: chgID, column: 0, band: .top)
        let c = CGPoint(x: 3840 + 1000, y: 500)
        let sel = engine.select(origin: .zero, cursor: c, displays: displays, anchor: anchor)
        #expect(sel == .span(display: sideID, span: ColumnSpan(columns: 1...1, band: .full)))
    }

    @Test func testAnchorAtCursor() {
        let a = engine.anchor(
            at: CGPoint(x: 1600, y: 1047 * 0.9), displays: [chg()])
        #expect(a == SpanAnchor(display: chgID, column: 2, band: .top))
    }

    @Test func testPortraitUsesRowsFromTopAndFullBand() {
        let p = portrait()
        // usable height 2511, 3 rows of 837, measured from the top (maxY = 2519).
        let top = engine.select(
            origin: .zero, cursor: CGPoint(x: -700, y: 2500), displays: [p], anchor: nil)
        let bottom = engine.select(
            origin: .zero, cursor: CGPoint(x: -700, y: 20), displays: [p], anchor: nil)
        #expect(top == .span(display: sideID, span: ColumnSpan(columns: 0...0, band: .full)))
        #expect(bottom == .span(display: sideID, span: ColumnSpan(columns: 2...2, band: .full)))
    }
}
