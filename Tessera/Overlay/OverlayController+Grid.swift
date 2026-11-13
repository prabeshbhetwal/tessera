import CoreGraphics
import TesseraCore

extension OverlayController {
    /// Faint cells outside `span` plus the top/bottom band split lines (landscape only; portrait spans
    /// ignore bands), the accent outlines of the cells inside `span`, and every full-height column
    /// rect (panel-local) for placing numbers.
    static func gridPaths(
        for display: DisplayContext, span: ColumnSpan, ring: RingSettings, offset: CGPoint
    ) -> (faint: CGPath, active: CGPath, columns: [CGRect]) {
        let faint = CGMutablePath()
        let active = CGMutablePath()
        var columns: [CGRect] = []
        for c in 0..<max(1, display.profile.columns) {
            let cell = GridGeometry.frame(for: ColumnSpan(columns: c...c, band: .full), display: display)
                .offsetBy(dx: -offset.x, dy: -offset.y)
            columns.append(cell)
            if span.columns.contains(c) {
                let picked = GridGeometry.frame(for: ColumnSpan(columns: c...c, band: span.band), display: display)
                active.addRoundedRect(in: picked.offsetBy(dx: -offset.x, dy: -offset.y), cornerWidth: 6, cornerHeight: 6)
            } else {
                faint.addRoundedRect(in: cell, cornerWidth: 6, cornerHeight: 6)
            }
        }
        if !display.range.isPortrait {
            let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
            let visible = display.visibleFrame
            for y in [visible.maxY - visible.height * CGFloat(ring.topBand), visible.minY + visible.height * CGFloat(ring.bottomBand)] {
                faint.move(to: CGPoint(x: usable.minX - offset.x, y: y - offset.y))
                faint.addLine(to: CGPoint(x: usable.maxX - offset.x, y: y - offset.y))
            }
        }
        return (faint, active, columns)
    }
}
