import AppKit
import QuartzCore
import TesseraCore

/// Renders one `PreviewLayers` value: dimmed neighbours, dashed "from" outline, tinted frame with
/// border, an optional image (window snapshot or app icon), and a label pill. Pure Core Animation.
@MainActor
final class PreviewLayer {
    let root = CALayer()
    private let dim = CAShapeLayer()
    private let fromOutlineHalo = CAShapeLayer()
    private let fromOutline = CAShapeLayer()
    private let fill = CALayer()
    /// Window snapshot (letterboxed to the frame) or app icon (centred). Full opacity, above the tint.
    private let image = CALayer()
    private let border = CALayer()
    private let pill = CALayer()
    private let text = CATextLayer()
    private var hasFrame = false

    // ponytail: no public API exposes a window's corner radius; 10 pt matches macOS 15 windows.
    private static let windowCornerRadius: CGFloat = 10
    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let pillPadding = CGSize(width: 12, height: 6)
    private static let maxIconSide: CGFloat = 96
    private static let imageFade = 0.15

    init() {
        for layer in [dim, fromOutlineHalo, fromOutline, fill, image, border, pill] as [CALayer] {
            root.addSublayer(layer)
        }
        pill.addSublayer(text)
        dim.fillColor = CGColor(gray: 0, alpha: 1)
        for outline in [fromOutlineHalo, fromOutline] {
            outline.fillColor = nil
            outline.lineDashPattern = [6, 4]
            outline.lineCap = .round
        }
        fromOutlineHalo.strokeColor = CGColor(gray: 0, alpha: 0.35)
        fromOutlineHalo.lineWidth = 3.5
        fromOutline.strokeColor = CGColor(gray: 1, alpha: 0.9)
        fromOutline.lineWidth = 1.5
        image.masksToBounds = true
        image.contentsGravity = .resizeAspect
        // The border carries a soft shadow so the preview lifts off the windows beneath it.
        border.shadowColor = CGColor(gray: 0, alpha: 1)
        border.shadowOpacity = 0.3
        border.shadowRadius = 8
        border.shadowOffset = CGSize(width: 0, height: -2)
        pill.backgroundColor = CGColor(gray: 0.08, alpha: 0.78)
        pill.borderColor = CGColor(gray: 1, alpha: 0.14)
        pill.borderWidth = 0.5
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
        fromOutlineHalo.frame = bounds
        for layer in [root, dim, fromOutlineHalo, fromOutline, fill, image, border, pill, text] as [CALayer] {
            layer.contentsScale = scale
        }
    }

    func clear() {
        root.isHidden = true
        hasFrame = false
        image.contents = nil
    }

    /// `offset` is the panel origin in global AppKit coordinates; every rect in `layers` is global.
    /// `theme` supplies every colour: preview, label pill and text, outline and dimming.
    func render(
        _ layers: PreviewLayers, image picture: CGImage?, offset: CGPoint,
        style: PreviewSettings, theme: Theme, animate: Bool
    ) {
        root.isHidden = false
        func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -offset.x, dy: -offset.y) }
        let accent = HexColor.cgColor(theme.previewHex)

        let dimPath = CGMutablePath()
        for r in layers.dimRects { dimPath.addRect(local(r)) }
        dim.path = dimPath
        dim.fillColor = HexColor.cgColor(theme.dimHex)
        dim.opacity = Float(style.dimStrength)
        let outline = layers.fromOutline.map {
            CGPath(roundedRect: local($0), cornerWidth: Self.windowCornerRadius, cornerHeight: Self.windowCornerRadius, transform: nil)
        }
        fromOutline.path = outline
        fromOutlineHalo.path = outline
        fromOutline.strokeColor = HexColor.cgColor(theme.outlineHex, alpha: 0.9)
        // A light outline gets a dark halo and a dark one a light halo, so it reads on any wallpaper.
        fromOutlineHalo.strokeColor = CGColor(gray: HexColor.isLight(theme.outlineHex) ? 0 : 1, alpha: 0.35)
        pill.backgroundColor = HexColor.cgColor(theme.labelHex, alpha: 0.82)
        text.foregroundColor = HexColor.cgColor(theme.labelTextHex)

        let radius = style.useWindowCornerRadius ? Self.windowCornerRadius : CGFloat(style.cornerRadius)
        fill.cornerRadius = radius
        fill.backgroundColor = accent
        fill.opacity = Float(style.opacity)
        let shown = layers.style == .tint ? nil : picture
        if shown != nil, image.contents == nil, animate {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.duration = Self.imageFade
            image.add(fade, forKey: "fade")
        }
        image.contents = shown
        image.cornerRadius = layers.style == .snapshot ? radius : 0
        border.cornerRadius = radius
        border.borderColor = accent
        border.borderWidth = CGFloat(style.borderWidth)

        // First appearance jumps; only later selection changes morph.
        let response: Double? = animate && hasFrame ? layers.springResponse : nil
        let target = local(layers.frame)
        place(fill, target, response)
        place(image, layers.style == .appIcon ? Self.iconFrame(in: target) : target, response)
        place(border, target, response)
        placeLabel(layers.label, in: target, position: style.labelPosition, response: response)
        hasFrame = true
    }

    /// Square centred in `frame`, a third of its short side, capped at `maxIconSide`.
    private static func iconFrame(in frame: CGRect) -> CGRect {
        let side = min(maxIconSide, min(frame.width, frame.height) / 3)
        return CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
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
