import SwiftUI
import TesseraCore

/// Motion pane stage: a window snapping from the left half to the right at the snap speed, with the time it
/// takes drawn as a bar. Instant jumps; under Reduce Motion every speed jumps, as on screen.
struct MotionDemo: View {
    let settings: TesseraSettings

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.stage, settings: settings)
        let seconds = settings.snapSeconds
        let speed = SnapSpeed(seconds: seconds)?.displayName ?? "Custom"
        let time = seconds <= 0 ? "no time at all" : "\(seconds.formatted(.number.precision(.fractionLength(0...2)))) s"
        let frames = [WindowAction.leftHalf, .rightHalf].enumerated().map { i, action in
            StageFrame(windows: [DemoWindow(id: 0, frame: GridGeometry.frame(for: action, display: display, current: display.visibleFrame), live: true)],
                       caption: i == 0 ? "Snap it to the other half." : "\(speed): the move takes \(time).",
                       seconds: seconds)
        }
        StagePlayer(display: display, settings: settings, frames: frames,
                    detail: "The same speed for the ring and shortcuts.", anchor: "Speed") { index in
            // The time the move takes, on a scale from instant to the slowest allowed.
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
                                .frame(width: index == 1 ? geometry.size.width * max(seconds / SnapSpeed.maxSeconds, 0.02) : 0)
                        }
                }
                .frame(height: 8)
                HStack {
                    Text("Instant")
                    Spacer()
                    Text("1 s")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}
