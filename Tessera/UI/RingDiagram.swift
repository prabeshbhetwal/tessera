import SwiftUI
import TesseraCore

/// Scaled drawing of the ring with the same wedge geometry and glyphs as the overlay. `active` is filled
/// in the accent colour like the live ring; `focused` is outlined for the Ring pane's picker.
///
/// `glide` and `hover` drive the picker's hover highlight. `glide` is a wedge position (0 = Up, clockwise)
/// that may be fractional and unwrapped (9 is Up-right, -1 is Up-left), so a spring between two wedges moves
/// the highlight along the arc the short way round. `hover` (0…1) fades the highlight in and lifts the tile
/// under it; neighbours swell a little as it passes, which is what makes the move read as one flowing glide.
struct RingDiagram: View, @MainActor Animatable {
    let ring: RingSettings
    let fill: Color
    let tint: Double
    let stroke: Color
    let accent: Color
    let active: Int?
    let focused: Int?
    var showBoundary: Bool
    var showFocusRing = false
    var glide: Double = 0
    var hover: Double = 0

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(glide, hover) }
        set { glide = newValue.first; hover = newValue.second }
    }

    /// How much the tile under the highlight grows at full hover.
    private static let lift: CGFloat = 0.08

    /// Diagram scale: the ring itself fills the diagram. The point threshold is drawn at true proportion
    /// and simply runs off the edge when it is far outside the ring, which is what it does on screen too.
    private static func scale(_ ring: RingSettings, in size: CGSize, showBoundary: Bool) -> CGFloat {
        let outer = RingGeometry.extent(ring)
        let reach = showBoundary ? min(max(CGFloat(ring.flickDistance), outer), outer * 1.6) : outer
        return (min(size.width, size.height) / 2 - 16) / max(reach, 1)
    }

    /// Wedge index in the direction of `point` (view coordinates, y down), or nil at the very centre.
    static func wedge(at point: CGPoint, size: CGSize) -> Int? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x, dy = center.y - point.y
        guard hypot(dx, dy) > 4 else { return nil }
        let deg = atan2(dx, dy) * 180 / .pi
        let shifted = ((deg + 22.5).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return min(Int(shifted / 45), 7)
    }

    /// Distance between two wedge positions around the ring, 0…4.
    static func wedgeDistance(_ a: Double, _ b: Double) -> Double {
        let d = ((a - b).truncatingRemainder(dividingBy: 8) + 8).truncatingRemainder(dividingBy: 8)
        return min(d, 8 - d)
    }

    var body: some View {
        Canvas { context, size in
            let s = Self.scale(ring, in: size, showBoundary: showBoundary)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var scaled = ring
            scaled.radius = ring.radius * s
            scaled.thickness = ring.thickness * s
            // RingLayer paths are y-up; flip into the Canvas.
            func flipped(_ path: Path) -> Path {
                path.applying(CGAffineTransform(scaleX: 1, y: -1)).offsetBy(dx: center.x, dy: center.y)
            }

            if showBoundary {
                let flick = CGFloat(ring.flickDistance) * s
                let circle = Path(ellipseIn: CGRect(x: center.x - flick, y: center.y - flick, width: flick * 2, height: flick * 2))
                context.fill(circle, with: .color(accent.opacity(0.06)))
                context.stroke(circle, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                let dead = CGFloat(ring.cancelRadius) * s  // the cancel area
                context.fill(Path(ellipseIn: CGRect(x: center.x - dead, y: center.y - dead, width: dead * 2, height: dead * 2)),
                             with: .color(.secondary.opacity(0.25)))
            }

            // The hover highlight, under the glyphs, at a point on the arc between wedges while it glides.
            if hover > 0.001 {
                let base = RingGeometry.glyphRect(index: 0, center: .zero, ring: scaled, aspect: 1.6)
                let radius = hypot(base.midX, base.midY)
                let angle = CGFloat.pi / 2 - CGFloat(glide) * .pi / 4
                let rect = CGRect(x: cos(angle) * radius - base.width / 2, y: sin(angle) * radius - base.height / 2,
                                  width: base.width, height: base.height).insetBy(dx: -6, dy: -5)
                let plate = flipped(Path(roundedRect: rect, cornerRadius: 6, style: .continuous))
                // Neutral, so the accent outline stays the one sign of the selected wedge.
                context.fill(plate, with: .color(.primary.opacity(0.10 * hover)))
                context.stroke(plate, with: .color(.primary.opacity(0.32 * hover)), lineWidth: 1)
            }

            for i in 0..<8 {
                let near = hover * max(0, 1 - Self.wedgeDistance(Double(i), glide))
                let box = RingGeometry.tilePath(index: i, center: .zero, ring: scaled).boundingBox
                let grow = 1 + Self.lift * CGFloat(near)
                let lift = CGAffineTransform(translationX: box.midX, y: box.midY)
                    .scaledBy(x: grow, y: grow).translatedBy(x: -box.midX, y: -box.midY)
                func lifted(_ path: CGPath) -> Path { flipped(Path(path).applying(lift)) }

                if ring.iconStyle == .layouts {
                    context.fill(lifted(RingGeometry.tilePath(index: i, center: .zero, ring: scaled)),
                                 with: .color(fill.opacity(max(tint, 0.85))))
                }
                guard let glyph = RingLayer.glyphPaths(ring: scaled, center: .zero, aspect: 1.6, only: i) else { continue }
                if active == i {
                    context.stroke(lifted(glyph.outlines), with: .color(stroke), lineWidth: 1.5)
                    context.fill(lifted(glyph.fills), with: .color(accent))
                } else {
                    context.stroke(lifted(glyph.outlines), with: .color(stroke.opacity(0.65 + 0.35 * near)), lineWidth: 1.25)
                    context.fill(lifted(glyph.fills), with: .color(stroke.opacity(0.28 + 0.32 * near)))
                }
            }
            if let focused {
                let wedge = flipped(Path(RingGeometry.tilePath(index: focused, center: .zero, ring: scaled)))
                context.stroke(wedge, with: .color(accent), lineWidth: showFocusRing ? 3 : 2)
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)),
                         with: .color(stroke.opacity(0.35)))
        }
        .background {
            if showFocusRing {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
            }
        }
    }
}
