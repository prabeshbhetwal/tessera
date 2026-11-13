import SwiftUI
import TesseraCore

/// Ring pane demo: the ring over a mock window, a flick in each direction in turn, and the preview where that
/// direction sends the window (`GridGeometry`, as the overlay computes it).
struct RingDemo: View {
    let settings: TesseraSettings

    static let directions = ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left"]

    var body: some View {
        let ring = settings.ring
        let display = DemoDisplay.context(DemoDisplay.laptop, settings: settings)
        let window = DemoDisplay.loose(on: display)
        let wedges = Array(ring.wedges.prefix(8))
        DemoColumn(title: "Flick") {
            DemoPlayer(title: "Ring", count: ring.directions ? wedges.count : 1, describe: { step in
                guard ring.directions, wedges.indices.contains(step) else {
                    return "Flicks are off. Point at a column instead."
                }
                return "Flick \(Self.directions[step].lowercased()): \(wedges[step].displayName)."
            }) { step in
                let action = ring.directions && wedges.indices.contains(step) ? wedges[step] : nil
                MockDesktop(
                    display: display, windows: [DemoWindow(id: 0, frame: window, live: true)],
                    preview: action.map { GridGeometry.frame(for: $0, display: display, current: window) }
                ) { map in
                    let r = map(window)
                    ringDiagram(active: action == nil ? nil : step)
                        .frame(width: 110, height: 110)
                        .position(x: r.midX, y: r.midY)
                }
            }
        }
    }

    private func ringDiagram(active: Int?) -> some View {
        let theme = settings.activeTheme
        return RingDiagram(ring: settings.ring, fill: Color(hex: theme.ring.fillHex), tint: theme.ring.opacity,
                           stroke: Color(hex: theme.ring.strokeHex), accent: Color(hex: theme.accentHex),
                           active: active, focused: nil, showBoundary: false)
            .opacity(settings.ring.showRing ? 1 : 0.2)
    }
}
