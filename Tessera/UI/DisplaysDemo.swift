import SwiftUI
import TesseraCore

/// Displays pane demo: the columns a new laptop screen and a new ultrawide would get from the sizing, gap and
/// padding settings, sized by `SizingRule` exactly as a real display is.
struct DisplaysDemo: View {
    let settings: TesseraSettings

    var body: some View {
        let screens = [("14-inch laptop", DemoDisplay.laptop), ("34-inch ultrawide", DemoDisplay.ultrawide)]
            .map { ($0.0, DemoDisplay.context($0.1, settings: settings)) }
        DemoColumn(title: "New displays") {
            DemoPlayer(title: "Displays", count: 1, describe: { _ in
                screens.map { "\($0.0): \(Self.columns($0.1))" }.joined(separator: ". ") + "."
            }, caption: false) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(screens, id: \.0) { name, display in
                        VStack(alignment: .leading, spacing: 4) {
                            MiniGrid(display: display)
                                .aspectRatio(display.visibleFrame.width / display.visibleFrame.height, contentMode: .fit)
                            Text("\(name) · \(Self.columns(display))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
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
