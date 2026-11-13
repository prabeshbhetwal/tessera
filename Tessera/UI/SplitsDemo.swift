import SwiftUI
import TesseraCore

/// Splits pane demo: three tiled mock windows. One edge is dragged and its neighbour follows (`SplitReflow`);
/// then the middle window closes and the one beside it fills the gap (`SplitFill`). Each half follows its switch.
struct SplitsDemo: View {
    let settings: TesseraSettings

    private static let captions = [
        "Three windows side by side.",
        "Drag the first window’s edge.",
        "Close the middle window.",
    ]

    var body: some View {
        let display = DemoDisplay.context(CGSize(width: 2560, height: 1440), settings: settings)
        DemoColumn(title: "Adjust and close") {
            DemoPlayer(title: "Splits", count: 3, describe: { step in
                Self.captions[step] + outcome(step)
            }) { step in
                MockDesktop(display: display, windows: windows(step, display: display))
            }
        }
    }

    private var reflows: Bool { settings.learnSplits && settings.splitReflowsNeighbours }
    private var fills: Bool { settings.learnSplits && settings.splitFillsClosedGap }

    private func outcome(_ step: Int) -> String {
        switch step {
        case 1: reflows ? " Its neighbour follows." : " Its neighbour stays put."
        case 2: fills ? " The window beside it fills the gap." : " The gap stays open."
        default: ""
        }
    }

    /// The windows at `step`, by the same code that moves real windows.
    private func windows(_ step: Int, display: DisplayContext) -> [DemoWindow] {
        let tiles = GridGeometry.tiles(3, display: display)
        guard step > 0, tiles.count == 3 else { return tiles.enumerated().map { DemoWindow(id: $0, frame: $1) } }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let gap = display.profile.gap
        var dragged = tiles
        dragged[0].size.width += usable.width * 0.12
        let adjusted = reflows ? SplitReflow.frames(before: tiles, after: dragged, usable: usable, gap: gap) ?? dragged : dragged
        guard step > 1 else {
            return adjusted.enumerated().map { DemoWindow(id: $0, frame: $1, live: $0 == 0) }
        }
        // The first window was used last, so it is the one that grows into the gap when it can.
        let left = [adjusted[0], adjusted[2]]
        let after = fills ? SplitFill.frames(filling: adjusted[1], frames: left, gap: gap) ?? left : left
        return [DemoWindow(id: 0, frame: after[0]), DemoWindow(id: 2, frame: after[1])]
    }
}
