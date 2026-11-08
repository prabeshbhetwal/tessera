import SwiftUI

/// Looping sketch of a flick: a cursor dot leaves the centre and lights the wedge it heads for.
struct FlickDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sequence = [6, 2, 0, 3, 7]

    var body: some View {
        // 30 fps is plenty for a decorative demo; the default follows the display (120 Hz on ProMotion)
        // and cost ~25% CPU for as long as onboarding stayed open.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
                let cycle = Int(t / 1.6)
                let phase = CGFloat(min(1, (t.truncatingRemainder(dividingBy: 1.6)) / 0.8))
                let wedge = sequence[cycle % sequence.count]
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2 - 8
                let inner = outer * 0.55

                for i in 0..<8 {
                    // RingLayer draws in y-up space; flip vertically for Canvas.
                    let path = Path(RingLayer.wedgePath(index: i, center: .zero, inner: inner, outer: outer))
                        .applying(CGAffineTransform(scaleX: 1, y: -1))
                        .offsetBy(dx: center.x, dy: center.y)
                    let lit = i == wedge && phase > 0.5
                    context.fill(path, with: .color(lit ? .accentColor : .secondary.opacity(0.25)))
                }
                let angle = CGFloat(wedge) * .pi / 4
                let distance = (inner + outer) / 2 * phase
                let dot = CGPoint(x: center.x + sin(angle) * distance, y: center.y - cos(angle) * distance)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Animation: the cursor moves outward and the ring highlights the wedge it heads for.")
    }
}
