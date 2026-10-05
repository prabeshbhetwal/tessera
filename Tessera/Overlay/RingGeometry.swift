import CoreGraphics
import TesseraCore

/// Icon positions follow the gesture directions; no enclosing tiles or circular band are drawn.
enum RingGeometry {
    static func tileRect(index: Int, center: CGPoint, ring: RingSettings) -> CGRect {
        let radius = CGFloat(ring.radius)
        let width = min(max(CGFloat(ring.thickness) * 1.55, 16), radius * 0.68)
        let height = min(max(CGFloat(ring.thickness) * 1.4, 14), radius * 0.62)
        let angle = CGFloat.pi / 2 - CGFloat(index) * .pi / 4
        return CGRect(x: center.x + cos(angle) * radius - width / 2,
                      y: center.y + sin(angle) * radius - height / 2, width: width, height: height)
    }

    static func tilePath(index: Int, center: CGPoint, ring: RingSettings) -> CGPath {
        let rect = glyphRect(index: index, center: center, ring: ring, aspect: 1.6).insetBy(dx: 0.5, dy: 0.5)
        let corner = min(rect.height * 0.16, 1.5)
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    static func path(center: CGPoint, ring: RingSettings) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<8 { path.addPath(tilePath(index: index, center: center, ring: ring)) }
        return path
    }

    static func extent(_ ring: RingSettings) -> CGFloat {
        let rect = glyphRect(index: 0, center: .zero, ring: ring, aspect: 1.6)
        return hypot(rect.maxX, rect.maxY)
    }

    static func glyphRect(index: Int, center: CGPoint, ring: RingSettings, aspect: CGFloat) -> CGRect {
        let tile = tileRect(index: index, center: center, ring: ring)
        let height = tile.height * 0.57
        let width = min(height * min(max(aspect, 1.2), 1.7), tile.width - 5)
        return CGRect(x: tile.midX - width / 2, y: tile.midY - height / 2, width: width, height: height)
    }

    static func shortName(_ action: WindowAction) -> String {
        switch action {
        case .maximize: "Fill"
        case .center: "Centre"
        case .leftHalf: "Left"
        case .rightHalf: "Right"
        case .topHalf: "Top"
        case .bottomHalf: "Bottom"
        case .topLeftQuarter: "Top L"
        case .topRightQuarter: "Top R"
        case .bottomLeftQuarter: "Low L"
        case .bottomRightQuarter: "Low R"
        }
    }
}
