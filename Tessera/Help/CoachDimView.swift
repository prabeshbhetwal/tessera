import AppKit
import QuartzCore

/// The coach's dimming: the theme's dim colour and strength with rounded spotlight cut-outs, a 2 pt accent outline
/// round them, and an optional pulsing seam. Its panel ignores the mouse, so clicks and drags reach the real windows.
@MainActor
final class CoachDimView: NSView {
    private let dim = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let seam = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        dim.fillRule = .evenOdd
        outline.fillColor = nil
        outline.lineWidth = 2
        for layer in [dim, outline, seam] { self.layer?.addSublayer(layer) }
    }

    required init?(coder: NSCoder) { fatalError("CoachDimView is built in code") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [dim, outline, seam] { layer.contentsScale = scale }
    }

    /// `spotlights` and `seamRect` are in this view's coordinates. `outlined` draws the accent edge round the spotlights.
    func update(spotlights: [CGRect], seamRect: CGRect?, outlined: Bool, dimColor: CGColor, accent: CGColor,
                description: String) {
        setAccessibilityLabel(description)
        let holes = CGMutablePath()
        for rect in spotlights {
            let radius = min(10, rect.width / 2, rect.height / 2)
            holes.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        // Spotlights that overlap would cancel each other out under even-odd, so merge them first.
        let merged = holes.normalized(using: .winding)
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(merged)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window?.backingScaleFactor ?? 2
        for layer in [dim, outline, seam] {
            layer.frame = bounds
            layer.contentsScale = scale
        }
        dim.fillColor = dimColor
        dim.path = path
        outline.path = outlined ? merged : nil
        outline.strokeColor = accent
        seam.removeAllAnimations()
        seam.opacity = 1
        seam.fillColor = accent
        seam.path = seamRect.map {
            let radius = min($0.width, $0.height) / 2
            return CGPath(roundedRect: $0, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        CATransaction.commit()

        guard seamRect != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.4
        pulse.toValue = 1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        seam.add(pulse, forKey: "pulse")
    }
}
