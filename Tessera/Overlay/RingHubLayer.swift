import AppKit
import QuartzCore
import TesseraCore

/// An unframed display glyph for column selections; never draws a centre card or orbital arc.
@MainActor
final class RingHubLayer {
    let root = CALayer()
    private let plate = CALayer()
    private let screen = CAShapeLayer()
    private let guide = CAShapeLayer()
    private let destination = CAShapeLayer()
    private let direction = CAShapeLayer()
    private var center = CGPoint.zero
    private var screenRect = CGRect.zero
    private var radius: CGFloat = 0
    private var lastRect: CGRect?

    init() {
        root.name = "column-preview"
        destination.name = "destination-preview"
        guide.name = "idle-guide"
        for layer in [direction, plate, screen, guide, destination] as [CALayer] { root.addSublayer(layer) }
        plate.cornerRadius = 10
        plate.borderWidth = 0.5
        plate.shadowColor = CGColor(gray: 0, alpha: 1)
        plate.shadowOpacity = 0.18
        plate.shadowRadius = 7
        plate.shadowOffset = CGSize(width: 0, height: -2)
        screen.fillColor = nil
        screen.lineWidth = 1
        guide.fillColor = nil
        guide.lineWidth = 0.5
        direction.fillColor = nil
        direction.lineWidth = 1.5
        direction.lineCap = .round
    }

    func configure(bounds: CGRect, center: CGPoint, ring: RingSettings, theme: Theme, scale: CGFloat) {
        self.center = center
        radius = CGFloat(ring.radius)
        let size = CGSize(width: radius * 0.82, height: radius * 0.68)
        plate.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                             width: size.width, height: size.height)
        plate.cornerRadius = min(size.height * 0.27, 12)
        plate.isHidden = true
        direction.isHidden = true
        plate.backgroundColor = HexColor.cgColor(theme.ring.fillHex, alpha: 0.92)
        plate.borderColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.14)
        screenRect = plate.frame.insetBy(dx: size.width * 0.18, dy: size.height * 0.23)
        root.frame = bounds
        for layer in [root, plate, screen, guide, destination, direction] { layer.contentsScale = scale }
        for layer in [screen, guide, destination, direction] { layer.frame = bounds }
        screen.path = CGPath(roundedRect: screenRect, cornerWidth: 2, cornerHeight: 2, transform: nil)
        screen.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.65)
        destination.fillColor = HexColor.cgColor(theme.accentHex)
        direction.strokeColor = HexColor.cgColor(theme.accentHex, alpha: 0.7)
        let grid = CGMutablePath()
        grid.move(to: CGPoint(x: screenRect.midX, y: screenRect.minY))
        grid.addLine(to: CGPoint(x: screenRect.midX, y: screenRect.maxY))
        grid.move(to: CGPoint(x: screenRect.minX, y: screenRect.midY))
        grid.addLine(to: CGPoint(x: screenRect.maxX, y: screenRect.midY))
        guide.path = grid
        guide.isHidden = false
        guide.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.18)
        lastRect = nil
        destination.path = nil
        direction.path = nil
        root.isHidden = false
    }

    func select(_ unit: CGRect?, direction index: Int? = nil) {
        if unit != lastRect {
            lastRect = unit
            let inset = screenRect.insetBy(dx: 2, dy: 2)
            destination.path = unit.map {
                CGPath(roundedRect: CGRect(x: inset.minX + $0.minX * inset.width,
                                           y: inset.minY + $0.minY * inset.height,
                                           width: inset.width * $0.width, height: inset.height * $0.height),
                       cornerWidth: 1, cornerHeight: 1, transform: nil)
            }
            guide.isHidden = unit != nil
        }
        if let index {
            let angle = CGFloat.pi / 2 - CGFloat(index) * .pi / 4
            let path = CGMutablePath()
            path.addArc(center: center, radius: radius * 0.51,
                        startAngle: angle - .pi / 10, endAngle: angle + .pi / 10, clockwise: false)
            direction.path = path
        } else { direction.path = nil }
    }

    func setCancelling(_ on: Bool) { plate.borderWidth = on ? 1 : 0.5 }
}
