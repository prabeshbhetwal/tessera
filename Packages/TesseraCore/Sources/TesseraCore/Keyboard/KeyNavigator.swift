import CoreGraphics

/// Keyboard selection while the ring is open (M2 spec §3).
public struct NavState: Equatable, Sendable {
    /// Index into the displays ordered by frame.minX then frame.minY.
    public var displayIndex: Int
    /// 0-based, inclusive.
    public var columns: ClosedRange<Int>
    public var band: Band

    public init(displayIndex: Int, columns: ClosedRange<Int>, band: Band) {
        self.displayIndex = displayIndex
        self.columns = columns
        self.band = band
    }
}

/// Pure reducer for the ring's navigation keys.
///
/// Every function takes the caller's `displays` in any order and sorts them itself, so a
/// `NavState.displayIndex` always refers to the same left-to-right order as `DisplayResolver.ordered`.
public enum KeyNavigator {
    /// The window's display and the column under its centre, band `.full`. Falls back to display 0,
    /// column 0 when there is no window or it is on no display. Nil only when there are no displays.
    public static func start(windowFrame: CGRect?, displays: [DisplayContext]) -> NavState? {
        let ordered = ordered(displays)
        guard !ordered.isEmpty else { return nil }
        guard let frame = windowFrame else { return NavState(displayIndex: 0, columns: 0...0, band: .full) }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        guard let index = ordered.firstIndex(where: { $0.frame.contains(centre) }) else {
            return NavState(displayIndex: 0, columns: 0...0, band: .full)
        }
        let d = ordered[index]
        let usable = GridGeometry.usableFrame(d.visibleFrame, profile: d.profile)
        let column = GridGeometry.index(at: centre, in: usable, count: d.profile.columns, portrait: d.range.isPortrait)
        return NavState(displayIndex: index, columns: column...column, band: .full)
    }

    public static func reduce(_ s: NavState, _ key: NavKey, displays: [DisplayContext]) -> NavState {
        let ordered = ordered(displays)
        guard !ordered.isEmpty else { return s }
        var s = clamped(s, ordered)
        let n = columnCount(ordered[s.displayIndex])
        let lo = s.columns.lowerBound, hi = s.columns.upperBound

        switch key {
        case .left: s.columns = max(lo - 1, 0)...max(lo - 1, 0)
        case .right: s.columns = min(hi + 1, n - 1)...min(hi + 1, n - 1)
        case .extendLeft: s.columns = max(lo - 1, 0)...hi
        case .extendRight: s.columns = lo...min(hi + 1, n - 1)
        case .bandUp: s.band = s.band == .bottom ? .full : .top
        case .bandDown: s.band = s.band == .top ? .full : .bottom
        case .column(let c):
            let i = min(max(c - 1, 0), n - 1)
            s.columns = i...i
        case .columnsPlus, .columnsMinus, .apply:
            break  // already re-clamped to the display's current column count
        case .nextDisplay, .previousDisplay:
            let step = key == .nextDisplay ? 1 : ordered.count - 1
            let to = (s.displayIndex + step) % ordered.count
            s.columns = relocate(s.columns, from: n, to: columnCount(ordered[to]))
            s.displayIndex = to
        }
        return s
    }

    public static func selection(_ s: NavState, displays: [DisplayContext]) -> Selection {
        let ordered = ordered(displays)
        guard !ordered.isEmpty else { return .none }
        let s = clamped(s, ordered)
        return .span(display: ordered[s.displayIndex].id, span: ColumnSpan(columns: s.columns, band: s.band))
    }

    // MARK: - Private

    /// Same rule as `DisplayResolver.ordered`: frame.minX, then frame.minY.
    private static func ordered(_ displays: [DisplayContext]) -> [DisplayContext] {
        displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    private static func columnCount(_ d: DisplayContext) -> Int { max(d.profile.columns, 1) }

    /// Display index and columns forced into range, so a stale state (display unplugged, column count
    /// lowered) never indexes out of bounds or yields an empty span.
    private static func clamped(_ s: NavState, _ ordered: [DisplayContext]) -> NavState {
        let index = min(max(s.displayIndex, 0), ordered.count - 1)
        let n = columnCount(ordered[index])
        let lo = min(max(s.columns.lowerBound, 0), n - 1)
        let hi = min(max(s.columns.upperBound, lo), n - 1)
        return NavState(displayIndex: index, columns: lo...hi, band: s.band)
    }

    /// Keeps the column ratio: `round(start*to/from)...max(start', round((end+1)*to/from)-1)`.
    private static func relocate(_ span: ClosedRange<Int>, from: Int, to: Int) -> ClosedRange<Int> {
        let ratio = Double(to) / Double(from)
        let start = min(Int((Double(span.lowerBound) * ratio).rounded()), to - 1)
        let end = min(max(start, Int((Double(span.upperBound + 1) * ratio).rounded()) - 1), to - 1)
        return start...end
    }
}
