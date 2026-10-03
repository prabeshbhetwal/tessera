import AppKit
import QuartzCore
import TesseraCore

/// Renders one `PreviewLayers` value: dimmed neighbours, dashed "from" outline,
/// tinted/thumbnail frame with border, and a label pill. Pure Core Animation.
@MainActor
final class PreviewLayer {
    let root = CALayer()
    private let dim = CAShapeLayer()
    private let fromOutline = CAShapeLayer()
    private let fill = CALayer()
    private let border = CALayer()
    private let pill = CALayer()
    private let text = CATextLayer()
    private var hasFrame = false

    // ponytail: no public API exposes a window's corner radius; 10 pt matches macOS 15 windows.
    private static let windowCornerRadius: CGFloat = 10
    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let pillPadding = CGSize(width: 12, height: 5)

    init() {
        for layer in [dim, fromOutline, fill, border, pill] as [CALayer] {
            root.addSublayer(layer)
        }
        pill.addSublayer(text)
        dim.fillColor = CGColor(gray: 0, alpha: 1)
        fromOutline.fillColor = nil
        fromOutline.strokeColor = CGColor(gray: 1, alpha: 0.85)
        fromOutline.lineWidth = 1.5
        fromOutline.lineDashPattern = [6, 4]
        fill.masksToBounds = true
        fill.contentsGravity = .resizeAspectFill
        pill.backgroundColor = CGColor(gray: 0, alpha: 0.72)
        text.font = Self.labelFont
        text.fontSize = Self.labelFont.pointSize
        text.foregroundColor = CGColor(gray: 1, alpha: 1)
        text.alignmentMode = .center
        root.isHidden = true
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        root.frame = bounds
        dim.frame = bounds
        fromOutline.frame = bounds
        for layer in [root, dim, fromOutline, fill, border, pill, text] as [CALayer] {
            layer.contentsScale = scale
        }
    }

    func clear() {
        root.isHidden = true
        hasFrame = false
        fill.contents = nil
    }

    /// `offset` is the panel origin in global AppKit coordinates; every rect in `layers` is global.
    func render(
        _ layers: PreviewLayers, thumbnail: CGImage?, offset: CGPoint,
        style: PreviewSettings, accent: CGColor, animate: Bool
    ) {
        root.isHidden = false
        func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -offset.x, dy: -offset.y) }

        let dimPath = CGMutablePath()
        for r in layers.dimRects { dimPath.addRect(local(r)) }
        dim.path = dimPath
        dim.opacity = Float(style.dimStrength)
        fromOutline.path = layers.fromOutline.map { CGPath(rect: local($0), transform: nil) }

        let radius = style.useWindowCornerRadius ? Self.windowCornerRadius : CGFloat(style.cornerRadius)
        fill.cornerRadius = radius
        fill.backgroundColor = accent
        fill.opacity = Float(style.opacity)
        fill.contents = layers.showThumbnail ? thumbnail : nil
        border.cornerRadius = radius
        border.borderColor = accent
        border.borderWidth = CGFloat(style.borderWidth)

        // First appearance jumps; only later selection changes morph.
        let response: Double? = animate && hasFrame ? layers.springResponse : nil
        let target = local(layers.frame)
        place(fill, target, response)
        place(border, target, response)
        placeLabel(layers.label, in: target, position: style.labelPosition, response: response)
        hasFrame = true
    }

    private func placeLabel(_ label: String?, in frame: CGRect, position: LabelPosition, response: Double?) {
        guard let label else {
            pill.isHidden = true
            return
        }
        pill.isHidden = false
        if text.string as? String != label { text.string = label }
        let size = (label as NSString).size(withAttributes: [.font: Self.labelFont])
        let textSize = CGSize(width: ceil(size.width), height: ceil(size.height))
        let pillSize = CGSize(
            width: textSize.width + Self.pillPadding.width * 2,
            height: textSize.height + Self.pillPadding.height * 2
        )
        pill.cornerRadius = pillSize.height / 2
        text.frame = CGRect(origin: CGPoint(x: Self.pillPadding.width, y: Self.pillPadding.height), size: textSize)
        let centerY = position == .bottom ? frame.minY + pillSize.height / 2 + 16 : frame.midY
        let pillFrame = CGRect(
            x: frame.midX - pillSize.width / 2, y: centerY - pillSize.height / 2,
            width: pillSize.width, height: pillSize.height
        )
        place(pill, pillFrame, response)
    }

    /// Sets the model frame, then springs from the current on-screen (presentation) value so
    /// retargeting mid-flight stays continuous.
    private func place(_ layer: CALayer, _ frame: CGRect, _ response: Double?) {
        let fromPosition = layer.presentation()?.position ?? layer.position
        let fromBounds = layer.presentation()?.bounds ?? layer.bounds
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        guard let response, fromPosition != layer.position || fromBounds != layer.bounds else {
            if response == nil { layer.removeAllAnimations() }
            return
        }
        layer.add(
            Self.spring("position", from: NSValue(point: fromPosition), to: NSValue(point: layer.position), response),
            forKey: "position"
        )
        layer.add(
            Self.spring("bounds", from: NSValue(rect: fromBounds), to: NSValue(rect: layer.bounds), response),
            forKey: "bounds"
        )
    }

    private static func spring(_ keyPath: String, from: NSValue, to: NSValue, _ response: Double) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: response, bounce: 0)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }
}
