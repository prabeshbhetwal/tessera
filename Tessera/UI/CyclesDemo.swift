import SwiftUI
import TesseraCore

/// Cycles pane demo: pick a cycle; each simulated press of its shortcut runs the step `CycleTracker` picks,
/// on a mock window, and the window goes where `TargetResolver` sends it.
struct CyclesDemo: View {
    let settings: TesseraSettings
    @State private var selected: String?

    var body: some View {
        let cycles = settings.cycles
        let cycle = cycles.first { $0.name == selected } ?? cycles.first
        let display = DemoDisplay.context(DemoDisplay.laptop, settings: settings)
        let start = DemoDisplay.loose(on: display)
        DemoColumn(title: "Press again") {
            if let cycle {
                Picker("Cycle", selection: Binding(get: { cycle.name }, set: { selected = $0 })) {
                    ForEach(cycles, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .accessibilityLabel("Cycle to demonstrate")
                let n = cycle.steps.count
                DemoPlayer(title: "Cycle", count: max(n, 1), describe: { press in
                    guard n > 0 else { return "This cycle has no steps, so its shortcut does nothing." }
                    let i = Self.step(afterPresses: press + 1, of: cycle)
                    return "Press \(press + 1): step \(i + 1) of \(n), \(cycle.steps[i].summary)."
                }) { press in
                    let frame = n == 0 ? start : TargetResolver.frame(
                        for: cycle.steps[Self.step(afterPresses: press + 1, of: cycle)], display: display, current: start)
                    MockDesktop(display: display, windows: [DemoWindow(id: 0, frame: frame, live: true)])
                }
                .id(cycle.name)
            } else {
                Caption("No cycles yet.")
            }
        }
    }

    /// The step the app runs on the last of `presses` quick presses on one window, by the app's own tracker.
    static func step(afterPresses presses: Int, of cycle: Cycle) -> Int {
        var tracker = CycleTracker()
        var index = 0
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for press in 0..<max(presses, 1) {
            index = tracker.step(cycle: cycle.name, windowKey: "demo", stepCount: cycle.steps.count,
                                 now: start.addingTimeInterval(Double(press)))
        }
        return index
    }
}
