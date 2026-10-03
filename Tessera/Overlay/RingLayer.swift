import QuartzCore
import TesseraCore

/// Eight-wedge radial menu drawn over a vibrant material (see `OverlayController`). The layers here are the
/// paint on top of that material: a tint, hairline wedge edges, the active wedge in the accent colour, a
/// small screen glyph per wedge showing its layout, and a dashed circle where pointing at the grid starts.
@MainActor
final class RingLayer {
    let root = CALayer()
    private let tint = CAShapeLayer()
    private let edges = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let glyphOutlines = CAShapeLayer()
    private let glyphFills = CAShapeLayer()
    private let boundaryHalo = CAShapeLayer()
    private let boundary = CAShapeLayer()
    private var center = CGPoint.zero
    private var inner: CGFloat = 0
    private var outer: CGFloat = 0
    private var activeIndex: Int?

    init() {
        for layer in [boundaryHalo, boundary, tint, edges, highlight, glyphOutlines, glyphFills] { root.addSublayer(layer) }
        edges.fillColor = nil
        edges.lineWidth = 1
        glyphOutlines.lineWidth = 1
        glyphOutlines.fillColor = nil
        glyphOutlines.lineJoin = .round
        boundary.fillColor = nil
        boundary.lineWidth = 1.5
        boundary.lineDashPattern = [4, 5]
        boundaryHalo.fillColor = nil
        boundaryHalo.lineWidth = 3
        boundaryHalo.lineDashPattern = [4, 5]
        boundaryHalo.strokeColor = CGColor(gray: 0, alpha: 0.35)
        highlight.shadowOpacity = 0.35
        highlight.shadowRadius = 4
        highlight.shadowOffset = CGSize(width: 0, height: -1)
    }

    /// `center` is in this layer's local coordinates (AppKit orientation, y up).
    func configure(bounds: CGRect, center: CGPoint, ring: RingSettings, theme: Theme, scale: CGFloat) {
        for layer in [root, tint, edges, highlight, glyphOutlines, glyphFills, boundary, boundaryHalo] {
            layer.frame = bounds
            layer.contentsScale = scale
        }
        self.center = center
        let radii = Self.radii(ring)
        inner = radii.inner
        outer = radii.outer

        let path = Self.ringPath(center: center, inner: inner, outer: outer)
        tint.path = path
        tint.fillColor = HexColor.cgColor(theme.ring.fillHex, alpha: theme.ring.opacity)
        edges.path = path
        edges.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.22)
        highlight.fillColor = HexColor.cgColor(theme.accentHex, alpha: 0.92)

        glyphOutlines.lineWidth = ring.iconStyle == .arrows ? 1.6 : 1
        glyphOutlines.lineCap = .round
        let glyphColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.95)
        glyphOutlines.strokeColor = glyphColor
        glyphFills.fillColor = glyphColor
        let glyphs = ring.showGlyphs
            ? Self.glyphPaths(ring: ring, center: center, aspect: bounds.height > 0 ? bounds.width / bounds.height : 1.6)
            : nil
        glyphOutlines.path = glyphs?.outlines
        glyphFills.path = glyphs?.fills

        // The boundary only means something when both gestures are on.
        let flick = CGFloat(ring.flickDistance)
        let circle = ring.showBoundary && ring.directions && ring.pointing
            ? CGPath(ellipseIn: CGRect(x: center.x - flick, y: center.y - flick, width: flick * 2, height: flick * 2), transform: nil)
            : nil
        boundary.path = circle
        boundaryHalo.path = circle
        root.isHidden = !ring.showRing
        boundary.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.55)
        activeIndex = nil
        highlight.path = nil
        root.opacity = 1
    }

    func setActive(_ index: Int?) {
        guard index != activeIndex else { return }
        activeIndex = index
        highlight.path = index.map { Self.wedgePath(index: $0, center: center, inner: inner, outer: outer) }
    }

    /// The ring stays visible but recedes while the grid is the focus.
    func setPointMode(_ on: Bool) {
        root.opacity = on ? 0.35 : 1
    }

    // MARK: - Geometry shared with the material mask and the Settings diagram

    /// Inner and outer radius of the drawn band. The inner edge never collapses below 0.
    nonisolated static func radii(_ ring: RingSettings) -> (inner: CGFloat, outer: CGFloat) {
        let half = max(1, CGFloat(ring.thickness)) / 2
        return (max(CGFloat(ring.radius) - half, 0), max(CGFloat(ring.radius) + half, 2))
    }

    /// All eight wedges as one path.
    nonisolated static func ringPath(center: CGPoint, inner: CGFloat, outer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<8 {
            path.addPath(wedgePath(index: i, center: center, inner: inner, outer: outer))
        }
        return path
    }

    /// One icon per wedge, centred on the ring: a screen with its layout filled in, or an arrow pointing the
    /// wedge's way (`ring.iconStyle`). Nil when the ring is too thin to fit one.
    nonisolated static func glyphPaths(ring: RingSettings, center: CGPoint, aspect: CGFloat) -> (outlines: CGPath, fills: CGPath)? {
        let height = CGFloat(ring.thickness) * 0.42
        guard height >= 5 else { return nil }
        if ring.iconStyle == .arrows { return arrowPaths(ring: ring, center: center, size: height * 1.15) }
        let width = min(height * min(max(aspect, 1.2), 2.2), CGFloat(ring.radius) * 0.6)
        let outlines = CGMutablePath()
        let fills = CGMutablePath()
        for (i, action) in ring.wedges.prefix(8).enumerated() {
            let angle = CGFloat.pi / 2 - CGFloat(i) * .pi / 4
            let mid = CGPoint(x: center.x + cos(angle) * CGFloat(ring.radius), y: center.y + sin(angle) * CGFloat(ring.radius))
            let screen = CGRect(x: mid.x - width / 2, y: mid.y - height / 2, width: width, height: height)
            outlines.addRoundedRect(in: screen.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 1.5, cornerHeight: 1.5)
            let u = unitRect(action)
            let inner = screen.insetBy(dx: 2, dy: 2)
            let cell = CGRect(x: inner.minX + u.minX * inner.width, y: inner.minY + u.minY * inner.height,
                              width: u.width * inner.width, height: u.height * inner.height)
            fills.addRoundedRect(in: cell, cornerWidth: 0.75, cornerHeight: 0.75)
        }
        return (outlines, fills)
    }

    /// An outward arrow per wedge: a shaft and a two-line head, stroked like the screen outlines.
    nonisolated private static func arrowPaths(ring: RingSettings, center: CGPoint, size: CGFloat) -> (outlines: CGPath, fills: CGPath) {
        let path = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat.pi / 2 - CGFloat(i) * .pi / 4
            let d = CGPoint(x: cos(angle), y: sin(angle))
            let mid = CGPoint(x: center.x + d.x * CGFloat(ring.radius), y: center.y + d.y * CGFloat(ring.radius))
            let tail = CGPoint(x: mid.x - d.x * size / 2, y: mid.y - d.y * size / 2)
            let tip = CGPoint(x: mid.x + d.x * size / 2, y: mid.y + d.y * size / 2)
            path.move(to: tail)
            path.addLine(to: tip)
            for turn in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
                let a = angle + turn
                path.move(to: tip)
                path.addLine(to: CGPoint(x: tip.x + cos(a) * size * 0.45, y: tip.y + sin(a) * size * 0.45))
            }
        }
        return (path, CGMutablePath())
    }

    /// The action's share of the screen in a unit square, y up.
    nonisolated static func unitRect(_ action: WindowAction) -> CGRect {
        switch action {
        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topLeftQuarter: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRightQuarter: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeftQuarter: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRightQuarter: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        }
    }

    /// Wedge `index` is centred `index * 45°` clockwise from straight up, in y-up coordinates.
    nonisolated static func wedgePath(index: Int, center: CGPoint, inner: CGFloat, outer: CGFloat) -> CGPath {
        let gap = 1.5 * CGFloat.pi / 180
        let mid = CGFloat.pi / 2 - CGFloat(index) * .pi / 4
        let start = mid - .pi / 8 + gap
        let end = mid + .pi / 8 - gap
        let path = CGMutablePath()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
