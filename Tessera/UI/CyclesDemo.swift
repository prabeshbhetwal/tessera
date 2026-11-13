import SwiftUI
import TesseraCore

/// Cycles pane stage: the cycle's shortcut pressed again and again on one window. Each press runs the step
/// `CycleTracker` picks, and the window goes where `TargetResolver` sends it. Pointing at a cycle plays that one.
struct CyclesDemo: View {
    let settings: TesseraSettings
    @Environment(DemoCueState.self) private var cues: DemoCueState?

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.stage, settings: settings)
        let cued: Cycle? = if case .cycle(let name) = cues?.cue { settings.cycles.first { $0.name == name } } else { nil }
        let cycle = cued ?? settings.cycles.first
        let keys = cycle.flatMap { c in settings.hotkeys.first { $0.command == .cycle(name: c.name) }?.hotkey }
        StagePlayer(display: display, settings: settings, frames: frames(cycle, keys: keys, display: display)) { index in
            VStack(spacing: 14) {
                if let keys, !keys.isNone {
                    HStack(spacing: 6) { ForEach(Array(keys.keycaps.enumerated()), id: \.offset) { Keycap($1, prominent: true) } }
                }
                if let cycle { steps(cycle, lit: index > 0 ? Self.step(afterPresses: index, of: cycle) : nil) }
            }
        }
    }

    private func steps(_ cycle: Cycle, lit: Int?) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(cycle.steps.enumerated()), id: \.offset) { i, step in
                Text(step.summary)
                    .font(.caption.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .foregroundStyle(i == lit ? Color.white : Color.primary)
                    .background(Capsule().fill(i == lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
            }
        }
    }

    private func frames(_ cycle: Cycle?, keys: Hotkey?, display: DisplayContext) -> [StageFrame] {
        let start = DemoDisplay.loose(on: display)
        let resting = StageFrame(windows: [DemoWindow(id: 0, frame: start, live: true)], caption: "No cycles yet.")
        guard let cycle else { return [resting] }
        guard !cycle.steps.isEmpty else { return [StageFrame(windows: resting.windows, caption: "\(cycle.name) has no steps, so it does nothing.")] }
        let press = keys.map { $0.isNone ? "its shortcut" : $0.displayString } ?? "its shortcut"
        var frames = [StageFrame(windows: resting.windows, caption: "\(cycle.name): press \(press) again and again.")]
        for presses in 1...cycle.steps.count {
            let i = Self.step(afterPresses: presses, of: cycle)
            let frame = TargetResolver.frame(for: cycle.steps[i], display: display, current: start)
            frames.append(StageFrame(windows: [DemoWindow(id: 0, frame: frame, live: true)],
                                     caption: "Press \(presses): step \(i + 1) of \(cycle.steps.count), \(cycle.steps[i].summary)."))
        }
        return frames
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
