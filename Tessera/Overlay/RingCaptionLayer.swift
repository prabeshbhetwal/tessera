import AppKit
import QuartzCore
import TesseraCore

/// A stable two-line caption below the dial; never follows the pointer or steals focus.
@MainActor
final class RingCaptionLayer {
    let root = CALayer()
    private let surface = CALayer()
    private let title = CATextLayer()
    private let hint = CATextLayer()
    private var anchor = CGPoint.zero
    private var above: CGFloat = 0
    private var bounds = CGRect.zero
    private var last: RingFeedback?
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let hintFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)

    init() {
        root.addSublayer(surface)
        surface.addSublayer(title)
        surface.addSublayer(hint)
        surface.cornerRadius = 13
        surface.borderWidth = 0.5
        surface.shadowColor = CGColor(gray: 0, alpha: 1)
        surface.shadowOpacity = 0.16
        surface.shadowRadius = 7
        surface.shadowOffset = CGSize(width: 0, height: -2)
        for (layer, font) in [(title, Self.titleFont), (hint, Self.hintFont)] {
            layer.font = font
            layer.fontSize = font.pointSize
            layer.alignmentMode = .center
            layer.truncationMode = .end
        }
    }

    func configure(bounds: CGRect, center: CGPoint, ring: RingSettings, theme: Theme, scale: CGFloat) {
        self.bounds = bounds
        anchor = CGPoint(x: center.x, y: center.y - RingGeometry.extent(ring) - 10)
        above = center.y + RingGeometry.extent(ring) + 10
        root.frame = bounds
        root.isHidden = !ring.showRing || !ring.showActionLabels || !bounds.contains(center)
        for layer in [root, surface, title, hint] { layer.contentsScale = scale }
        surface.backgroundColor = HexColor.cgColor(theme.labelHex, alpha: 0.96)
        surface.borderColor = HexColor.cgColor(theme.labelTextHex, alpha: 0.14)
        title.foregroundColor = HexColor.cgColor(theme.labelTextHex)
        hint.foregroundColor = HexColor.cgColor(theme.labelTextHex, alpha: 0.75)
        last = nil
    }

    func render(_ feedback: RingFeedback) {
        guard feedback != last else { return }
        last = feedback
        title.string = feedback.title
        hint.string = feedback.hint
        let titleWidth = (feedback.title as NSString).size(withAttributes: [.font: Self.titleFont]).width
        let hintWidth = (feedback.hint as NSString).size(withAttributes: [.font: Self.hintFont]).width
        let width = min(max(132, ceil(max(titleWidth, hintWidth)) + 24), max(1, bounds.width - 24))
        let height: CGFloat = 44
        let x = min(max(bounds.minX + 12, anchor.x - width / 2), bounds.maxX - width - 12)
        // Flip above the dial when there is no room below; clamp at the display edges.
        let desiredY = anchor.y - height < bounds.minY + 12 ? above : anchor.y - height
        let y = min(max(bounds.minY + 12, desiredY), bounds.maxY - height - 12)
        surface.frame = CGRect(x: x, y: y, width: width, height: height)
        surface.shadowPath = CGPath(roundedRect: surface.bounds, cornerWidth: 13, cornerHeight: 13, transform: nil)
        title.frame = CGRect(x: 12, y: 22, width: width - 24, height: 17)
        hint.frame = CGRect(x: 10, y: 6, width: width - 20, height: 13)
    }
}
