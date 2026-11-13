import CoreGraphics
import Testing

@testable import TesseraCore

/// `display(at:)` is closed at the top: CGEvent y = 0 maps to AppKit y = maxY of the top display, a point
/// `CGRect.contains` rejects. The cursor on the very top pixel row must still belong to its display.
@Suite struct DisplayHitTestTests {
    static func display(_ serial: UInt32, x: CGFloat, y: CGFloat = 0, width: CGFloat = 1000, height: CGFloat = 800)
        -> DisplayContext
    {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let range = ColumnRange(minCols: 1, maxCols: 8, defaultCols: 4, maxRows: 2, isPortrait: false)
        return DisplayContext(
            id: DisplayID(vendor: 1, model: 1, serial: serial, uuid: nil), frame: frame, visibleFrame: frame,
            range: range, profile: DisplayProfile(columns: 4, gap: 0, padding: 0))
    }

    static let left = display(1, x: 0)
    static let right = display(2, x: 1000)
    static let engine = SelectionEngine(ring: RingSettings())

    @Test func topPixelRowBelongsToItsDisplay() {
        // Real path: a CGEvent at the top-left origin row on a primary display 800 high.
        let top = CoordinateSpace.pointFromCG(CGPoint(x: 500, y: 0), primaryHeight: 800)
        #expect(top.y == 800)
        #expect([Self.left].display(at: top)?.id == Self.left.id)
        #expect(DisplayResolver.resolve(.cursor, displays: [Self.left], windowFrame: nil, cursor: top)?.id == Self.left.id)
    }

    @Test func everyEdgeOfAFrameIsInside() {
        let d = [Self.left]
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 1000, y: 0), CGPoint(x: 0, y: 800), CGPoint(x: 1000, y: 800)] {
            #expect(d.display(at: p)?.id == Self.left.id)
        }
    }

    @Test func pointJustOutsideStaysOutside() {
        let d = [Self.left]
        for p in [CGPoint(x: 500, y: 800.5), CGPoint(x: 1000.5, y: 400), CGPoint(x: -0.5, y: 400), CGPoint(x: 500, y: -0.5)] {
            #expect(d.display(at: p) == nil)
        }
    }

    /// The strict match must win where two displays share an edge, whichever order they are listed in.
    @Test func sharedEdgeBelongsToTheDisplayThatStartsThere() {
        let p = CGPoint(x: 1000, y: 400)
        #expect([Self.left, Self.right].display(at: p)?.id == Self.right.id)
        #expect([Self.right, Self.left].display(at: p)?.id == Self.right.id)
        // Stacked: the upper display starts at y 800, so y 800 is its own, not the lower one's top.
        let upper = Self.display(3, x: 0, y: 800)
        #expect([Self.left, upper].display(at: CGPoint(x: 500, y: 800))?.id == upper.id)
        #expect([upper, Self.left].display(at: CGPoint(x: 500, y: 800))?.id == upper.id)
    }

    @Test func pointingAndAnchorWorkOnTheTopPixelRow() {
        let top = CGPoint(x: 600, y: 800)
        let sel = Self.engine.select(origin: CGPoint(x: 600, y: 300), cursor: top, displays: [Self.left], anchor: nil)
        #expect(sel == .span(display: Self.left.id, span: ColumnSpan(columns: 2...2, band: .top)))
        #expect(Self.engine.anchor(at: top, displays: [Self.left]) == SpanAnchor(display: Self.left.id, column: 2, band: .top))
    }
}
