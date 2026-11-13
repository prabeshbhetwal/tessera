import SwiftUI
import TesseraCore

/// Splits pane stage: three tiled windows. The first window's edge is dragged and its neighbour follows
/// (`SplitReflow`); then the middle window closes and the window beside it fills the gap (`SplitFill`).
/// Each half follows its switch. Pointing at one of those switches plays just that half.
struct SplitsDemo: View {
    let settings: TesseraSettings
    @Environment(DemoCueState.self) private var cues: DemoCueState?

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.stage, settings: settings)
        let story = story(display: display)
        StagePlayer(display: display, settings: settings, frames: story, detail: detail)
    }

    private var detail: String {
        guard settings.learnSplits else { return "Learning is off, so windows stay as you leave them." }
        return "Resize neighbours \(settings.splitReflowsNeighbours ? "on" : "off") · "
            + "fill the space \(settings.splitFillsClosedGap ? "on" : "off")"
    }

    private var reflows: Bool { settings.learnSplits && settings.splitReflowsNeighbours }
    private var fills: Bool { settings.learnSplits && settings.splitFillsClosedGap }

    private func story(display: DisplayContext) -> [StageFrame] {
        let tiles = GridGeometry.tiles(3, display: display)
        guard tiles.count == 3 else { return [StageFrame(windows: [], caption: "")] }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let gap = display.profile.gap
        let start = StageFrame(windows: windows(tiles), caption: "Three windows side by side.")

        var dragged = tiles
        dragged[0].size.width += usable.width * 0.12
        let adjusted = reflows ? SplitReflow.frames(before: tiles, after: dragged, usable: usable, gap: gap) ?? dragged : dragged
        let drag = StageFrame(windows: windows(adjusted, live: 0), pointer: CGPoint(x: dragged[0].maxX, y: dragged[0].midY),
                               caption: reflows ? "Drag an edge: the neighbour follows." : "Drag an edge: the neighbour stays put.")

        // The pointer clicks the middle window's close button; the window closes. The first window was used last,
        // so it grows into the gap when it can.
        func close(_ frames: [CGRect]) -> [StageFrame] {
            var press = windows(frames)
            press[1].closing = true
            let left = [frames[0], frames[2]]
            let after = fills ? SplitFill.frames(filling: frames[1], frames: left, gap: gap) ?? left : left
            return [
                StageFrame(windows: press, pointer: press[1].closeButton, caption: "Close the middle window."),
                StageFrame(windows: [DemoWindow(id: 0, frame: after[0]), DemoWindow(id: 2, frame: after[1])],
                            pointer: press[1].closeButton,
                            caption: fills ? "It closes, and the window beside it fills the gap." : "It closes, and the gap stays open."),
            ]
        }
        switch cues?.cue {
        case .reflow: return [start, drag]
        case .fillGap: return [start] + close(tiles)
        default: return [start, drag] + close(adjusted)
        }
    }

    private func windows(_ frames: [CGRect], live: Int? = nil) -> [DemoWindow] {
        frames.enumerated().map { DemoWindow(id: $0, frame: $1, live: $0 == live) }
    }
}
