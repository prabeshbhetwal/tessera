/// The menu bar's Columns submenu for one display: only the counts that display allows, the current one ticked,
/// and One More / One Fewer greyed at the ends of the range, so no item quietly does something else.
public enum ColumnsMenu {
    public struct Entry: Equatable, Sendable {
        public let title: String
        public let change: ColumnChange
        public let enabled: Bool
        public let checked: Bool
    }

    /// The step items, then one item per count in `range`.
    public static func entries(range: ClosedRange<Int>, current: Int) -> [Entry] {
        [Entry(title: "One More Column", change: .delta(1), enabled: current < range.upperBound, checked: false),
         Entry(title: "One Fewer Column", change: .delta(-1), enabled: current > range.lowerBound, checked: false)]
            + range.map { count in
                Entry(title: count == 1 ? "1 Column" : "\(count) Columns", change: .set(count),
                      enabled: true, checked: count == current)
            }
    }
}
