import SwiftUI
import TesseraCore

/// Displays pane stage: the columns a new laptop screen (on the stage) and a new ultrawide (on the sheet) get from
/// the sizing, gap and padding settings, sized by `SizingRule` exactly as a real display is.
struct DisplaysDemo: View {
    let settings: TesseraSettings

    var body: some View {
        let laptop = DemoDisplay.context(DemoDisplay.laptop, settings: settings, menuBar: true)
        let ultrawide = DemoDisplay.context(DemoDisplay.ultrawide, settings: settings, menuBar: true)
        let caption = "A new 14-inch laptop gets \(Self.columns(laptop)); a new 34-inch ultrawide gets \(Self.columns(ultrawide))."
        StagePlayer(display: laptop, settings: settings,
                    frames: [StageFrame(windows: [], grid: true, caption: caption)]) { _ in
            VStack(spacing: 8) {
                MiniGrid(display: ultrawide)
                    .aspectRatio(ultrawide.visibleFrame.width / ultrawide.visibleFrame.height, contentMode: .fit)
                    .padding(6)
                    .stageGlass(cornerRadius: 10, clear: true)
                Text("34-inch ultrawide").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "4 columns (3–5)": the count a new display starts with and the range it allows.
    static func columns(_ display: DisplayContext) -> String {
        let r = display.range
        let range = r.minCols == r.maxCols ? "" : " (\(r.minCols)–\(r.maxCols))"
        return "\(display.profile.columns) \(display.profile.columns == 1 ? "column" : "columns")\(range)"
    }
}
