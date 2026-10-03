import CoreGraphics
import Foundation

/// Display lookup for commands (M2 spec §2). Order is `frame.minX`, then `frame.minY`, so "display 1" is the
/// leftmost screen.
public enum DisplayResolver {
    public static func ordered(_ displays: [DisplayContext]) -> [DisplayContext] {
        displays.sorted {
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            return $0.id.storageKey < $1.id.storageKey   // stable for identical origins
        }
    }

    /// `nil` when nothing matches (no window for `.current`, cursor off every screen, index or id unknown).
    public static func resolve(_ s: DisplaySelector, displays: [DisplayContext], windowFrame: CGRect?,
                               cursor: CGPoint) -> DisplayContext? {
        switch s {
        case .current:
            guard let w = windowFrame else { return nil }
            if let hit = displays.display(at: CGPoint(x: w.midX, y: w.midY)) { return hit }
            // Centre is off every screen (window dragged mostly out of view): take the largest overlap.
            return displays
                .map { ($0, area($0.frame.intersection(w))) }
                .filter { $0.1 > 0 }
                .max { $0.1 < $1.1 }?.0
        case .cursor:
            return displays.display(at: cursor)
        case .index(let n):
            let list = ordered(displays)
            return list.indices.contains(n - 1) ? list[n - 1] : nil
        case .id(let key):
            return displays.first { $0.id.storageKey == key }
        }
    }

    /// Wraps around at both ends. `nil` when `from` is not in `displays` or `.index` is out of range.
    public static func step(_ s: DisplayStep, from: DisplayContext, displays: [DisplayContext]) -> DisplayContext? {
        let list = ordered(displays)
        guard let i = list.firstIndex(where: { $0.id == from.id }) else { return nil }
        switch s {
        case .next: return list[(i + 1) % list.count]
        case .previous: return list[(i - 1 + list.count) % list.count]
        case .index(let n): return list.indices.contains(n - 1) ? list[n - 1] : nil
        }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}

/// Turns `Target`s into spans and frames for a concrete display.
public enum TargetResolver {
    /// 1-based or negative columns → 0-based, clamped to the display's column count. Never empty, never
    /// out of range. `nil` for `.action`.
    public static func span(for target: Target, display: DisplayContext) -> ColumnSpan? {
        guard case .span(let columns, let band) = target else { return nil }
        let n = max(display.profile.columns, 1)
        // 1... → v-1, -1 → n-1. 0 has no meaning and clamps to the first column.
        func index(_ v: Int) -> Int { min(max(v > 0 ? v - 1 : (v < 0 ? n + v : 0), 0), n - 1) }
        let a = index(columns.lowerBound), b = index(columns.upperBound)
        return ColumnSpan(columns: min(a, b)...max(a, b), band: band)
    }

    public static func frame(for target: Target, display: DisplayContext, current: CGRect) -> CGRect {
        switch target {
        case .action(let action):
            return GridGeometry.frame(for: action, display: display, current: current)
        case .span:
            guard let s = span(for: target, display: display) else { return current }
            return GridGeometry.frame(for: s, display: display)
        }
    }

    /// Keeps the span's position by ratio when a window moves between grids of different column counts.
    public static func relocate(span: ColumnSpan, from: DisplayContext, to: DisplayContext) -> ColumnSpan {
        ColumnSpan(columns: relocate(span.columns, from: from.profile.columns, to: to.profile.columns), band: span.band)
    }

    /// `round(start*to/from) … max(start', round((end+1)*to/from) - 1)`, clamped to `0..<to`. Shared by
    /// the ring's Tab key and "move to display", so both land on the same columns.
    public static func relocate(_ columns: ClosedRange<Int>, from: Int, to: Int) -> ClosedRange<Int> {
        let f = Double(max(from, 1)), t = max(to, 1)
        let ratio = Double(t) / f
        let start = min(max(Int((Double(columns.lowerBound) * ratio).rounded()), 0), t - 1)
        let endRaw = Int((Double(columns.upperBound + 1) * ratio).rounded()) - 1
        let end = min(max(start, endRaw), t - 1)
        return start...end
    }
}
