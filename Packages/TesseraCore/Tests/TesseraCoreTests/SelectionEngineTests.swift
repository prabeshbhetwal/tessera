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
        // The ring's whole empty middle (radius − thickness / 2 = 39 pt by default) selects nothing.
        let edge = CGPoint(x: origin.x + 38.99, y: origin.y)
        #expect(engine.select(origin: origin, cursor: edge, displays: [chg()], anchor: nil) == .none)
    }

    /// The reported bug: with the dead zone at 0, pressing and releasing without moving picked wedge 0
    /// (atan2(0, 0) points up) and maximised the window. Standing still or jittering never picks anything.
    @Test func testZeroDeadZoneStillIgnoresNoMoveAndJitter() {
        var ring = RingSettings()
        ring.deadZone = 0
        let e = SelectionEngine(ring: ring)
        #expect(e.select(origin: origin, cursor: origin, displays: [chg()], anchor: nil) == .none)
        #expect(e.select(origin: origin, cursor: CGPoint(x: origin.x + 2, y: origin.y + 2), displays: [chg()], anchor: nil) == .none)
        let pastCancel = CGPoint(x: origin.x + ring.cancelRadius + 1, y: origin.y)
        #expect(e.select(origin: origin, cursor: pastCancel, displays: [chg()], anchor: nil)
            == .wedge(index: 2, action: .rightHalf), "a deliberate move past the cancel area still works")
    }

    @Test func testTilesSplitTheDisplayEqually() {
        let d = chg()
        let three = GridGeometry.tiles(3, display: d)
        #expect(three.count == 3)
        let widths = three.map(\.width)
        #expect(widths.max()! - widths.min()! < 0.5, "equal shares")
        #expect(three[0].minX < three[1].minX && three[1].minX < three[2].minX, "left to right")
        let usable = GridGeometry.usableFrame(d.visibleFrame, profile: d.profile)
        #expect(abs(three[0].minX - usable.minX) < 0.5 && abs(three[2].maxX - usable.maxX) < 0.5, "fills the display")
        #expect(GridGeometry.tiles(0, display: d).isEmpty)
        #expect(GridGeometry.tiles(1, display: d) == [GridGeometry.frame(for: .maximize, display: d, current: .zero)])
    }

    @Test func testFlickBoundaries() {
        let d = [chg()]
        let at10 = CGPoint(x: origin.x + RingSettings().cancelRadius, y: origin.y)
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

    /// The cell under the cursor is the cell GridGeometry draws, whatever the padding: an oversized
    /// padding is clamped the same way on both sides, so the highlighted column is the hit column.
    @Test func testCellMatchesGridGeometryForAnyPadding() {
        for padding in [0.0, 8, 300, 600, 2000] {
            let base = chg()
            let d = DisplayContext(
                id: chgID, visibleFrame: base.visibleFrame, range: base.range,
                profile: DisplayProfile(columns: 5, gap: 8, padding: padding))
            for x in stride(from: 1.0, to: 3840, by: 97) {
                let p = CGPoint(x: x, y: 500)
                guard case .span(_, let span) = engine.select(origin: .zero, cursor: p, displays: [d], anchor: nil) else {
                    Issue.record("expected a span at x=\(x) padding=\(padding)")
                    continue
                }
                let drawn = GridGeometry.frame(for: span, display: d)
                let usable = GridGeometry.usableFrame(d.visibleFrame, profile: d.profile)
                let clampedX = min(max(x, usable.minX), usable.maxX - 0.001)
                #expect(drawn.minX - 4 <= clampedX && clampedX <= drawn.maxX + 4, "x=\(x) padding=\(padding) span=\(span)")
            }
        }
    }

    // Review fix: the menu bar / Dock strips belong to the display (no dead zone).
    @Test func testMenuBarAndDockStripsSelectDisplay() {
        let base = chg()
        let d = DisplayContext(
            id: chgID, frame: CGRect(x: 0, y: -60, width: 3840, height: 1140),  // Dock below, menu bar above
            visibleFrame: base.visibleFrame, range: base.range, profile: base.profile)
        let menuBar = engine.select(origin: .zero, cursor: CGPoint(x: 1600, y: 1070), displays: [d], anchor: nil)
        #expect(menuBar == .span(display: chgID, span: ColumnSpan(columns: 2...2, band: .top)))
        let dock = engine.select(origin: CGPoint(x: 2000, y: 500), cursor: CGPoint(x: 10, y: -30), displays: [d], anchor: nil)
        #expect(dock == .span(display: chgID, span: ColumnSpan(columns: 0...0, band: .bottom)))
        #expect(engine.anchor(at: CGPoint(x: 1600, y: 1070), displays: [d]) != nil)
        #expect(engine.select(origin: .zero, cursor: CGPoint(x: 1600, y: 1300), displays: [d], anchor: nil) == .none)
    }

    // MARK: Gesture switches

    @Test func directionsOffPointsPastTheCancelArea() {
        var ring = RingSettings()
        ring.directions = false
        let e = SelectionEngine(ring: ring)
        let near = CGPoint(x: origin.x + ring.cancelRadius + 5, y: origin.y)  // would be a wedge with directions on
        guard case .span = e.select(origin: origin, cursor: near, displays: [chg()], anchor: nil) else {
            Issue.record("expected a grid span")
            return
        }
        #expect(e.select(origin: origin, cursor: CGPoint(x: origin.x + 5, y: origin.y), displays: [chg()], anchor: nil) == .none)
    }

    @Test func pointingOffKeepsWedgesAtAnyDistance() {
        var ring = RingSettings()
        ring.pointing = false
        let e = SelectionEngine(ring: ring)
        let far = CGPoint(x: origin.x + 900, y: origin.y)
        #expect(e.select(origin: origin, cursor: far, displays: [chg()], anchor: nil) == .wedge(index: 2, action: .rightHalf))
    }

    @Test func bothGesturesOffSelectNothing() {
        var ring = RingSettings()
        ring.directions = false
        ring.pointing = false
        let e = SelectionEngine(ring: ring)
        for distance in [30.0, 200, 900] {
            #expect(e.select(origin: origin, cursor: CGPoint(x: origin.x + distance, y: origin.y), displays: [chg()], anchor: nil) == .none)
        }
    }
}
