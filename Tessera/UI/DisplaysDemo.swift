import SwiftUI
import TesseraCore

/// Displays pane stage: the columns a new laptop screen (on the stage) and a new ultrawide (on the sheet) get from
/// the sizing, gap and padding settings, sized by `SizingRule` exactly as a real display is.
struct DisplaysDemo: View {
    let settings: TesseraSettings

    var body: some View {
        let laptop = DemoDisplay.context(DemoDisplay.laptop, settings: settings, menuBar: true)
        let ultrawide = DemoDisplay.context(DemoDisplay.ultrawide, settings: settings, menuBar: true)
        let caption = "Laptop: \(Self.columns(laptop)). Ultrawide: \(Self.columns(ultrawide))."
        let s = settings.sizing
        let detail = "Columns \(Int(s.minColumnWidth))–\(Int(s.maxColumnWidth)) pt wide, ideally \(Int(s.idealColumnWidth)) · "
            + "gap \(Int(settings.defaultGap)) · padding \(Int(settings.defaultPadding))"
        StagePlayer(display: laptop, settings: settings,
                    frames: [StageFrame(windows: [], grid: true, caption: caption)], detail: detail) { _ in
            // The second screen size, where the same widths give more columns.
            MiniGrid(display: ultrawide)
                .aspectRatio(ultrawide.visibleFrame.width / ultrawide.visibleFrame.height, contentMode: .fit)
                .frame(maxHeight: 64)
        }
    }

    /// "4 columns (3–5)": the count a new display starts with and the range it allows.
    static func columns(_ display: DisplayContext) -> String {
        let r = display.range
        let range = r.minCols == r.maxCols ? "" : " (\(r.minCols)–\(r.maxCols))"
        return "\(display.profile.columns) \(display.profile.columns == 1 ? "column" : "columns")\(range)"
    }
}
