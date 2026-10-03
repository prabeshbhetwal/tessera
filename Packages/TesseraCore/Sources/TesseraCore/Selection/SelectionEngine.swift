import CoreGraphics
import Foundation

/// Where a click-to-span started: the cell (column + band) under the cursor at click time.
/// For portrait displays `column` is the row index from the top.
public struct SpanAnchor: Equatable, Sendable {
    public let display: DisplayID
    public let column: Int
    public let band: Band

    public init(display: DisplayID, column: Int, band: Band) {
        self.display = display
        self.column = column
        self.band = band
    }
}

/// Pure flick/point selection (spec §4.2-4.4). Coordinates are AppKit global (y up).
public struct SelectionEngine: Sendable {
    public let ring: RingSettings
    /// Once pointing, the cursor must come this far back inside the flick distance to pick a direction
    /// again, so hovering on the boundary doesn't flicker between the ring and the grid.
    public static let pointHysteresis: Double = 8
    /// Hand and trackpad jitter while pressing the chord. A move shorter than this never picks anything,
    /// even with the dead zone set to 0, so pressing and releasing in place does nothing.
    public static let jitterTolerance: Double = 4

    public init(ring: RingSettings) { self.ring = ring }

    /// `pointing` is whether the previous selection was a grid span (see `pointHysteresis`).
    public func select(
        origin: CGPoint, cursor: CGPoint, displays: [DisplayContext], anchor: SpanAnchor?, pointing: Bool = false
    ) -> Selection {
        let dx = Double(cursor.x - origin.x)
        let dy = Double(cursor.y - origin.y)
        let distance = hypot(dx, dy)

        if distance < max(ring.deadZone, Self.jitterTolerance) { return .none }
        // Directions off: every move past the dead zone points. Pointing off: the wedges reach any distance.
        let inDirectionZone = distance < ring.flickDistance - (pointing ? Self.pointHysteresis : 0)
        if ring.directions, inDirectionZone || !ring.pointing { return wedge(dx: dx, dy: dy) }
        guard ring.pointing, let display = displays.display(at: cursor) else {
            return .none
        }
        let here = cell(at: cursor, in: display)
        var columns = here.column...here.column
        var band = here.band
        if let anchor, anchor.display == display.id {
            let last = max(1, display.profile.columns) - 1
            let a = min(max(anchor.column, 0), last)
            columns = min(a, here.column)...max(a, here.column)
            band = anchor.band == here.band ? here.band : .full
        }
        return .span(display: display.id, span: ColumnSpan(columns: columns, band: band))
    }

    public func anchor(at cursor: CGPoint, displays: [DisplayContext]) -> SpanAnchor? {
        guard let display = displays.display(at: cursor) else {
            return nil
        }
        let c = cell(at: cursor, in: display)
        return SpanAnchor(display: display.id, column: c.column, band: c.band)
    }

    // MARK: - Private

    private func wedge(dx: Double, dy: Double) -> Selection {
        guard !ring.wedges.isEmpty else { return .none }
        // Degrees clockwise from up. The epsilon keeps the lower edge of each wedge inclusive
        // despite atan2 rounding (22.5 deg must land in wedge 1, not 0).
        let deg = atan2(dx, dy) * 180 / .pi
        let shifted = (deg + 22.5 + 1e-9).truncatingRemainder(dividingBy: 360)
        let normalized = (shifted + 360).truncatingRemainder(dividingBy: 360)
        let index = min(Int(normalized / 45), ring.wedges.count - 1)
        return .wedge(index: index, action: ring.wedges[index])
    }

    /// Column (or row from the top, on portrait displays) and band under `p`. Same geometry as the
    /// frames GridGeometry draws, so the cell under the cursor is always the cell that lights up.
    private func cell(at p: CGPoint, in display: DisplayContext) -> (column: Int, band: Band) {
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let index = GridGeometry.index(at: p, in: usable, count: display.profile.columns, portrait: display.range.isPortrait)
        if display.range.isPortrait { return (index, .full) }

        let frame = display.visibleFrame
        let fraction = frame.height > 0 ? Double((p.y - frame.minY) / frame.height) : 0.5
        let band: Band =
            fraction >= 1 - ring.topBand ? .top : (fraction < ring.bottomBand ? .bottom : .full)
        return (index, band)
    }
}
