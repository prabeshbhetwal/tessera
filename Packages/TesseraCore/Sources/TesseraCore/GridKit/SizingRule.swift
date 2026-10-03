import CoreGraphics
import Foundation

/// Spec §3.3: derives the allowed column (or, for portrait, row) counts from a display's usable size.
public enum SizingRule {
    public static func range(for usable: CGSize, constants: SizingConstants) -> ColumnRange {
        let w = finite(usable.width), h = finite(usable.height)
        let isPortrait = h > w
        // Portrait uses the same rule with the axes swapped; the result then counts rows.
        let (long, short) = isPortrait ? (h, w) : (w, h)

        // A non-positive constant would divide by zero; treat it as 1 pt (still yields sane, capped counts).
        let maxWidth = max(constants.maxColumnWidth, 1)
        let minWidth = max(constants.minColumnWidth, 1)
        let idealWidth = max(constants.idealColumnWidth, 1)
        let rowHeight = max(constants.minRowHeight, 1)

        let minCols = max(1, count((long / maxWidth).rounded(.up)))
        // `max(lo, min(x, hi))` keeps maxCols >= minCols even if maxColumns < minCols.
        let maxCols = max(minCols, min(count((long / minWidth).rounded(.down)), max(constants.maxColumns, 1)))
        let ideal = count((long / idealWidth).rounded(.toNearestOrEven))
        let defaultCols = max(minCols, min(ideal, maxCols))
        let maxRows = max(1, count((short / rowHeight).rounded(.down)))

        return ColumnRange(minCols: minCols, maxCols: maxCols, defaultCols: defaultCols,
                           maxRows: maxRows, isPortrait: isPortrait)
    }

    /// NaN, infinities and negatives become 0.
    private static func finite(_ v: CGFloat) -> Double { v.isFinite ? max(Double(v), 0) : 0 }

    /// Safe Double -> Int; callers pass already-rounded, non-negative values.
    private static func count(_ v: Double) -> Int { v.isFinite ? Int(min(max(v, 0), 1_000_000)) : 0 }
}

extension DisplayProfile {
    /// The profile used when the user has no override: the range's default count, not persisted.
    public static func auto(range: ColumnRange, gap: Double, padding: Double) -> DisplayProfile {
        DisplayProfile(columns: range.defaultCols, gap: gap, padding: padding, isUserOverride: false)
    }

    /// Returns a copy with `columns` forced into `range` (never below 1, so no zero-width columns).
    public func clamped(to range: ColumnRange) -> DisplayProfile {
        var p = self
        p.columns = max(1, range.minCols, min(columns, range.maxCols))
        return p
    }
}
