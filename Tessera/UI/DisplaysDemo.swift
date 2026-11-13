import SwiftUI
import TesseraCore

/// Displays pane stage: the columns a new laptop screen (on the stage) and a new ultrawide (on the sheet) get from
/// the sizing, gap and padding settings, sized by `SizingRule` exactly as a real display is.
struct DisplaysDemo: View {
    let settings: TesseraSettings
    @Environment(DemoCueState.self) private var cues: DemoCueState?
    /// The ideal width when a drag on the column edge began.
    @State private var startIdeal: Double?

    var body: some View {
        let laptop = DemoDisplay.context(DemoDisplay.laptop, settings: settings, menuBar: true)
        let ultrawide = DemoDisplay.context(DemoDisplay.ultrawide, settings: settings, menuBar: true)
        let caption = "Laptop: \(Self.columns(laptop)). Ultrawide: \(Self.columns(ultrawide))."
        let s = settings.sizing
        let detail = "Columns \(Int(s.minColumnWidth))–\(Int(s.maxColumnWidth)) pt wide, ideally \(Int(s.idealColumnWidth)) · "
            + "gap \(Int(settings.defaultGap)) · padding \(Int(settings.defaultPadding))"
        StagePlayer(display: laptop, settings: settings,
                    frames: [StageFrame(windows: [], grid: true, caption: caption)], detail: detail,
                    anchor: "Ideal column width", overlay: { AnyView(edgeGrip(on: laptop, $0)) }) { _ in
            // The second screen size, where the same widths give more columns.
            MiniGrid(display: ultrawide)
                .aspectRatio(ultrawide.visibleFrame.width / ultrawide.visibleFrame.height, contentMode: .fit)
                .frame(maxHeight: 64)
        }
    }

    /// A grip on the first column's right edge. Dragging it sets the ideal column width, within the minimum and
    /// maximum, and the columns re-count live; Esc puts the width back.
    @ViewBuilder private func edgeGrip(on display: DisplayContext, _ geometry: StageGeometry) -> some View {
        if let apply = cues?.apply, display.profile.columns > 1 {
            let first = GridGeometry.frame(for: ColumnSpan(columns: 0...0, band: .full), display: display)
            let at = geometry.point(CGPoint(x: first.maxX + display.profile.gap / 2, y: first.midY))
            let s = settings.sizing
            StageGrip(begin: { startIdeal = s.idealColumnWidth }, change: { dx in
                guard let startIdeal else { return }
                let ideal = min(max(startIdeal + dx / geometry.scale, s.minColumnWidth), s.maxColumnWidth)
                // The slider's step.
                let stepped = (ideal / 8).rounded() * 8
                apply { $0.sizing.idealColumnWidth = stepped }
            }, cancel: {
                if let startIdeal { apply { $0.sizing.idealColumnWidth = startIdeal } }
            }, end: { startIdeal = nil })
            .position(at)
            Text("Ideal \(Int(s.idealColumnWidth)) pt")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
                .fixedSize()
                .position(x: at.x, y: at.y - 26)
                .allowsHitTesting(false)
        }
    }

    /// "4 columns (3–5)": the count a new display starts with and the range it allows.
    static func columns(_ display: DisplayContext) -> String {
        let r = display.range
        let range = r.minCols == r.maxCols ? "" : " (\(r.minCols)–\(r.maxCols))"
        return "\(display.profile.columns) \(display.profile.columns == 1 ? "column" : "columns")\(range)"
    }
}
