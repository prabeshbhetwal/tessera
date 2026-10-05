import AppKit
import QuartzCore
import TesseraCore

/// A light, icon-only direction palette. The destination gets the accent; the desktop stays visible.
@MainActor
final class RingLayer {
    let root = CALayer()
    private let tint = CAShapeLayer()
    private let edges = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let glyphOutlines = CAShapeLayer()
    private let glyphFills = CAShapeLayer()
    private let activeGlyphOutlines = CAShapeLayer()
    private let activeGlyphFills = CAShapeLayer()
    private let boundaryHalo = CAShapeLayer()
    private let boundary = CAShapeLayer()
    /// Kept separate from selection; the centre remains the cancellation area.
    private let cancelMark = CAShapeLayer()
    private var cancelling = false
    private var center = CGPoint.zero
    private var inner: CGFloat = 0
    private var outer: CGFloat = 0
    private var activeIndex: Int?
    private var spanVisible = false
    private var settings = RingSettings.default
    private var aspect: CGFloat = 1.6
    private var animate = false
    private let hub = RingHubLayer()

    init() {
        for layer in [boundaryHalo, boundary, tint, edges, highlight, glyphOutlines, glyphFills,
                      activeGlyphOutlines, activeGlyphFills, cancelMark] { root.addSublayer(layer) }
        edges.fillColor = nil
        edges.lineWidth = 1
        cancelMark.lineCap = .round
        glyphOutlines.lineWidth = 1
        glyphOutlines.fillColor = nil
        glyphOutlines.lineJoin = .round
        activeGlyphOutlines.fillColor = nil
        activeGlyphOutlines.lineJoin = .round
        activeGlyphOutlines.lineCap = .round
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
        root.addSublayer(hub.root)
    }

    /// `center` is in this layer's local coordinates (AppKit orientation, y up).
    func configure(bounds: CGRect, center: CGPoint, ring: RingSettings, theme: Theme, scale: CGFloat) {
        for layer in [root, tint, edges, highlight, glyphOutlines, glyphFills, activeGlyphOutlines,
                      activeGlyphFills, boundary, boundaryHalo, cancelMark] {
            layer.frame = bounds
            layer.contentsScale = scale
            layer.opacity = 1
        }
        self.center = center
        settings = ring
        aspect = 1.6
        animate = theme.preview.morph && theme.preview.springResponse > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let radii = Self.radii(ring)
        inner = radii.inner
        outer = radii.outer

        let path = RingGeometry.path(center: center, ring: ring)
        tint.path = ring.showGlyphs && ring.iconStyle == .layouts ? path : nil
        tint.fillColor = HexColor.cgColor(theme.ring.fillHex, alpha: theme.ring.opacity)
        tint.shadowColor = CGColor(gray: 0, alpha: 1)
        tint.shadowOpacity = 0.18
        tint.shadowRadius = 3
        tint.shadowOffset = .zero
        tint.shadowPath = tint.path
        edges.path = nil
        edges.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.16)
        highlight.fillColor = HexColor.cgColor(theme.accentHex)
        highlight.shadowColor = HexColor.cgColor(theme.accentHex)

        glyphOutlines.lineWidth = ring.iconStyle == .arrows ? 1.8 : 1.25
        activeGlyphOutlines.lineWidth = glyphOutlines.lineWidth + 0.25
        activeGlyphOutlines.strokeColor = HexColor.cgColor(theme.ring.strokeHex)
        activeGlyphFills.fillColor = HexColor.cgColor(theme.accentHex)
        glyphOutlines.lineCap = .round
        let glyphColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.65)
        glyphOutlines.strokeColor = glyphColor
        glyphFills.fillColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.28)
        for layer in [glyphOutlines, activeGlyphOutlines] {
            layer.shadowColor = CGColor(gray: HexColor.isLight(theme.ring.strokeHex) ? 0 : 1, alpha: 1)
            layer.shadowOpacity = 0.5
            layer.shadowRadius = 1.5
            layer.shadowOffset = .zero
        }
        let glyphs = ring.showGlyphs
            ? Self.glyphPaths(ring: ring, center: center, aspect: aspect)
            : nil
        glyphOutlines.path = glyphs?.outlines
        glyphFills.path = glyphs?.fills
        hub.configure(bounds: bounds, center: center, ring: ring, theme: theme, scale: scale)
        hub.root.isHidden = true

        // The boundary only means something when both gestures are on.
        let flick = CGFloat(ring.flickDistance)
        let circle = ring.showBoundary && ring.directions && ring.pointing
            ? CGPath(ellipseIn: CGRect(x: center.x - flick, y: center.y - flick, width: flick * 2, height: flick * 2), transform: nil)
            : nil
        boundary.path = circle
        boundaryHalo.path = circle
        root.isHidden = !ring.showRing
        boundary.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.55)

        cancelMark.path = CGPath(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25,
                                                  width: 2.5, height: 2.5), transform: nil)
        cancelMark.fillColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.8)
        cancelMark.lineWidth = 0
        cancelMark.strokeColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 1)
        cancelling = false
        cancelMark.opacity = 0.35
        activeIndex = nil
        spanVisible = false
        highlight.path = nil
        activeGlyphOutlines.path = nil
        activeGlyphFills.path = nil
        root.removeAllAnimations()
        root.opacity = 1
    }

    func setActive(_ index: Int?) {
        guard index != activeIndex || spanVisible else { return }
        spanVisible = false
        activeIndex = index
        highlight.path = nil
        let action = index.flatMap { settings.wedges.indices.contains($0) ? settings.wedges[$0] : nil }
        hub.select(action.map(Self.unitRect), direction: index)
        hub.root.isHidden = true
        let glyph = index.flatMap { selected in
            settings.showGlyphs ? Self.glyphPaths(ring: settings, center: center, aspect: aspect, only: selected) : nil
        }
        activeGlyphOutlines.path = glyph?.outlines
        activeGlyphFills.path = glyph?.fills
        guard animate, index != nil else { activeGlyphFills.removeAllAnimations(); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.45
        fade.toValue = 1
        fade.duration = 0.12
        activeGlyphFills.add(fade, forKey: "selection")
    }

    /// True while the cursor is in the empty middle, where releasing cancels.
    func setCancelling(_ on: Bool) {
        guard on != cancelling else { return }
        cancelling = on
        hub.setCancelling(on)
        cancelMark.opacity = on ? 1 : 0.35
    }

    /// The ring stays visible but recedes while the grid is the focus.
    func setPointMode(_ on: Bool) {
        for layer in [tint, edges, highlight, glyphOutlines, glyphFills, activeGlyphOutlines,
                      activeGlyphFills, boundary, boundaryHalo] { layer.opacity = on ? 0.25 : 1 }
    }

    func setCenterVisible(_ visible: Bool) { hub.root.isHidden = !visible; cancelMark.isHidden = !visible }

    func setSpan(_ span: ColumnSpan, columns: Int, portrait: Bool = false) {
        if activeIndex != nil { setActive(nil) }
        spanVisible = true
        hub.root.isHidden = !settings.showGlyphs
        let count = CGFloat(max(columns, 1))
        if portrait {
            hub.select(CGRect(x: 0, y: 1 - CGFloat(span.columns.upperBound + 1) / count,
                              width: 1, height: CGFloat(span.columns.count) / count))
            return
        }
        let y: CGFloat = span.band == .top ? 0.5 : 0
        hub.select(CGRect(x: CGFloat(span.columns.lowerBound) / count, y: y,
                          width: CGFloat(span.columns.count) / count, height: span.band == .full ? 1 : 0.5))
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
    nonisolated static func glyphPaths(ring: RingSettings, center: CGPoint, aspect: CGFloat, only index: Int? = nil) -> (outlines: CGPath, fills: CGPath)? {
        let height = RingGeometry.glyphRect(index: 0, center: center, ring: ring, aspect: aspect).height
        guard height >= 5 else { return nil }
        if ring.iconStyle == .arrows { return arrowPaths(ring: ring, center: center, size: height * 1.15, only: index) }
        let outlines = CGMutablePath()
        let fills = CGMutablePath()
        for (i, action) in ring.wedges.prefix(8).enumerated() {
            if let index, i != index { continue }
            let screen = RingGeometry.glyphRect(index: i, center: center, ring: ring, aspect: aspect)
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
    nonisolated private static func arrowPaths(ring: RingSettings, center: CGPoint, size: CGFloat, only index: Int?) -> (outlines: CGPath, fills: CGPath) {
        let path = CGMutablePath()
        for i in 0..<8 {
            if let index, i != index { continue }
            let angle = CGFloat.pi / 2 - CGFloat(i) * .pi / 4
            let d = CGPoint(x: cos(angle), y: sin(angle))
            let glyph = RingGeometry.glyphRect(index: i, center: center, ring: ring, aspect: 1.6)
            let mid = CGPoint(x: glyph.midX, y: glyph.midY)
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

    /// Compatibility geometry for the onboarding direction sketch.
    nonisolated static func wedgePath(index: Int, center: CGPoint, inner: CGFloat, outer: CGFloat) -> CGPath {
        var ring = RingSettings.default
        ring.radius = Double((inner + outer) / 2)
        ring.thickness = Double(max(1, outer - inner))
        return RingGeometry.tilePath(index: index, center: center, ring: ring)
    }
}
