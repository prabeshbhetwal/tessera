import QuartzCore
import TesseraCore

/// Eight-wedge radial menu. One shape layer holds all wedges; a second holds the active wedge in the accent colour.
@MainActor
final class RingLayer {
    let root = CALayer()
    private let wedges = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private var center = CGPoint.zero
    private var inner: CGFloat = 0
    private var outer: CGFloat = 0
    private var activeIndex: Int?

    init() {
        root.addSublayer(wedges)
        root.addSublayer(highlight)
        wedges.lineWidth = 1
    }

    /// `center` is in this layer's local coordinates (AppKit orientation, y up).
    func configure(bounds: CGRect, center: CGPoint, ring: RingSettings, theme: Theme, scale: CGFloat) {
        for layer in [root, wedges, highlight] {
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

    /// Wedge `index` is centred `index * 45°` clockwise from straight up, in y-up coordinates.
    static func wedgePath(index: Int, center: CGPoint, inner: CGFloat, outer: CGFloat) -> CGPath {
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
