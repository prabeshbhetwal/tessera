import SwiftUI
import TesseraCore

/// Motion pane demo: a mock window snapping between halves at the snap speed. Instant jumps; under Reduce
/// Motion every speed jumps, as on screen.
struct MotionDemo: View {
    let settings: TesseraSettings

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.laptop, settings: settings)
        let seconds = settings.snapSeconds
        let speed = SnapSpeed(seconds: seconds)?.displayName ?? "Custom"
        DemoColumn(title: "Snap") {
            DemoPlayer(title: "Snap speed", count: 2, describe: { step in
                let side = step == 0 ? "left" : "right"
                return seconds <= 0 ? "\(speed): the window jumps to the \(side) half."
                    : "\(speed): the window takes \(seconds.formatted(.number.precision(.fractionLength(0...2)))) s to reach the \(side) half."
            }, animation: seconds > 0 ? .easeInOut(duration: seconds) : nil) { step in
                let action: WindowAction = step == 0 ? .leftHalf : .rightHalf
                let frame = GridGeometry.frame(for: action, display: display, current: display.visibleFrame)
                MockDesktop(display: display, windows: [DemoWindow(id: 0, frame: frame, live: true)])
            }
        }
    }
}
