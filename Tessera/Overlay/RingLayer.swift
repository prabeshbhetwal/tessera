import QuartzCore
import TesseraCore

/// Eight-wedge radial menu. One shape layer holds all wedges; a second holds the active wedge in the accent colour.
/// Each wedge carries a tiny screen glyph of its layout; an optional dashed circle marks where pointing at the grid starts.
@MainActor
final class RingLayer {
    let root = CALayer()
    private let wedges = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let glyphOutlines = CAShapeLayer()
    private let glyphFills = CAShapeLayer()
    private let boundary = CAShapeLayer()
    /// ✕ in the empty middle: releasing there cancels. Brightens while the cursor is over it.
    private let cancelMark = CAShapeLayer()
    private var cancelling = false
    private var center = CGPoint.zero
    private var inner: CGFloat = 0
    private var outer: CGFloat = 0
    private var activeIndex: Int?

    init() {
        for layer in [boundary, wedges, highlight, glyphOutlines, glyphFills, cancelMark] { root.addSublayer(layer) }
        cancelMark.lineCap = .round
        wedges.lineWidth = 1
        glyphOutlines.lineWidth = 1
        glyphOutlines.fillColor = nil
        boundary.fillColor = nil
        boundary.lineWidth = 1.5
        boundary.lineDashPattern = [4, 5]
    }

    /// `center` is in this layer's local coordinates (AppKit orientation, y up).
    func configure(bounds: CGRect, center: CGPoint, ring: RingSettings, theme: Theme, scale: CGFloat) {
        for layer in [root, wedges, highlight, glyphOutlines, glyphFills, boundary, cancelMark] {
            layer.frame = bounds
            layer.contentsScale = scale
        }
        self.center = center
        let half = max(1, CGFloat(ring.thickness)) / 2
        outer = max(CGFloat(ring.radius) + half, 2)
        inner = max(CGFloat(ring.radius) - half, 0)

        let path = CGMutablePath()
        for i in 0..<8 {
            path.addPath(Self.wedgePath(index: i, center: center, inner: inner, outer: outer))
        }
        wedges.path = path
        wedges.fillColor = HexColor.cgColor(theme.ring.fillHex, alpha: theme.ring.opacity)
        wedges.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: min(1, theme.ring.opacity + 0.1))
        highlight.fillColor = HexColor.cgColor(theme.accentHex, alpha: 0.9)

        let glyphColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.9)
        glyphOutlines.strokeColor = glyphColor
        glyphFills.fillColor = glyphColor
        let glyphs = Self.glyphPaths(ring: ring, center: center, aspect: bounds.height > 0 ? bounds.width / bounds.height : 1.6)
        glyphOutlines.path = glyphs?.outlines
        glyphFills.path = glyphs?.fills

        let flick = CGFloat(ring.flickDistance)
        boundary.path = CGPath(ellipseIn: CGRect(x: center.x - flick, y: center.y - flick, width: flick * 2, height: flick * 2), transform: nil)
        boundary.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.45)

        let arm = CGFloat(min(ring.cancelRadius * 0.28, 7))
        let cross = CGMutablePath()
        cross.move(to: CGPoint(x: center.x - arm, y: center.y - arm))
        cross.addLine(to: CGPoint(x: center.x + arm, y: center.y + arm))
        cross.move(to: CGPoint(x: center.x - arm, y: center.y + arm))
        cross.addLine(to: CGPoint(x: center.x + arm, y: center.y - arm))
        cancelMark.path = cross
        cancelMark.lineWidth = 2
        cancelMark.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 1)
        cancelling = false
        cancelMark.opacity = 0.35
        boundary.isHidden = !ring.showBoundary
        activeIndex = nil
        highlight.path = nil
        root.opacity = 1
    }

    func setActive(_ index: Int?) {
        guard index != activeIndex else { return }
        activeIndex = index
        highlight.path = index.map { Self.wedgePath(index: $0, center: center, inner: inner, outer: outer) }
    }

    /// True while the cursor is in the empty middle, where releasing cancels.
    func setCancelling(_ on: Bool) {
        guard on != cancelling else { return }
        cancelling = on
        cancelMark.opacity = on ? 1 : 0.35
    }

    /// The ring stays visible but recedes while the grid is the focus.
    func setPointMode(_ on: Bool) {
        root.opacity = on ? 0.35 : 1
    }

    /// Screen-shaped glyph per wedge (outline + filled layout), centred on the ring. Nil when the ring is too thin.
    private static func glyphPaths(ring: RingSettings, center: CGPoint, aspect: CGFloat) -> (outlines: CGPath, fills: CGPath)? {
        let height = CGFloat(ring.thickness) * 0.42
        guard height >= 5 else { return nil }
        let width = min(height * min(max(aspect, 1.2), 2.2), CGFloat(ring.radius) * 0.6)
        let outlines = CGMutablePath()
        let fills = CGMutablePath()
        for (i, action) in ring.wedges.prefix(8).enumerated() {
            let angle = CGFloat.pi / 2 - CGFloat(i) * .pi / 4
            let mid = CGPoint(x: center.x + cos(angle) * CGFloat(ring.radius), y: center.y + sin(angle) * CGFloat(ring.radius))
            let screen = CGRect(x: mid.x - width / 2, y: mid.y - height / 2, width: width, height: height)
            outlines.addRect(screen.insetBy(dx: 0.5, dy: 0.5))
            let u = unitRect(action)
            let inner = screen.insetBy(dx: 2, dy: 2)
            fills.addRect(CGRect(x: inner.minX + u.minX * inner.width, y: inner.minY + u.minY * inner.height,
                                 width: u.width * inner.width, height: u.height * inner.height))
        }
        return (outlines, fills)
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
