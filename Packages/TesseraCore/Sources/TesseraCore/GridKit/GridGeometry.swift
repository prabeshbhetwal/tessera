import CoreGraphics
import Foundation

/// Pure grid math (spec §3.6). Everything is in AppKit global coordinates (bottom-left origin, y up).
public enum GridGeometry {
    /// The display's visible frame inset by its padding. Padding is clamped so the result is never negative-sized.
    public static func usableFrame(_ visible: CGRect, profile: DisplayProfile) -> CGRect {
        let p = min(max(profile.padding, 0), min(visible.width, visible.height) / 2)
        return visible.insetBy(dx: p, dy: p)
    }

    /// Column containing `x`, clamped to `0...columns-1`. `columns < 1` is treated as 1; NaN maps to 0.
    /// Landscape displays only; for portrait use `index(at:in:count:portrait:)`.
    public static func columnIndex(at x: CGFloat, in usable: CGRect, columns: Int) -> Int {
        slot(Double(x - usable.minX), extent: Double(usable.width), count: columns)
    }

    /// Slot under `point`: a column (x) for landscape, a row measured from the top for portrait.
    public static func index(at point: CGPoint, in usable: CGRect, count: Int, portrait: Bool) -> Int {
        portrait
            ? slot(Double(usable.maxY - point.y), extent: Double(usable.height), count: count)
            : columnIndex(at: point.x, in: usable, columns: count)
    }

    /// Frame for a column span (rows on portrait displays, where the span is full width and `band` is ignored).
    public static func frame(for span: ColumnSpan, display: DisplayContext) -> CGRect {
        let usable = usableFrame(display.visibleFrame, profile: display.profile)
        let n = max(display.profile.columns, 1)
        let lo = min(max(span.columns.lowerBound, 0), n - 1)
        let hi = min(max(span.columns.upperBound, lo), n - 1)
        let a = Double(lo) / Double(n), b = Double(hi + 1) / Double(n)   // b == 1 exactly for the last slot

        if display.range.isPortrait {
            return rect(in: usable, x: 0...1, y: (1 - b)...(1 - a), gap: display.profile.gap)
        }
        let y: ClosedRange<Double> = switch span.band {
        case .full: 0...1
        case .top: 0.5...1
        case .bottom: 0...0.5
        }
        return rect(in: usable, x: a...b, y: y, gap: display.profile.gap)
    }

    /// Frame for a display-relative action. `current` is only used by `.center`.
    public static func frame(for action: WindowAction, display: DisplayContext, current: CGRect) -> CGRect {
        let usable = usableFrame(display.visibleFrame, profile: display.profile)
        let gap = display.profile.gap
        switch action {
        case .maximize:          return rect(in: usable, x: 0...1, y: 0...1, gap: gap)
        case .leftHalf:          return rect(in: usable, x: 0...0.5, y: 0...1, gap: gap)
        case .rightHalf:         return rect(in: usable, x: 0.5...1, y: 0...1, gap: gap)
        case .topHalf:           return rect(in: usable, x: 0...1, y: 0.5...1, gap: gap)
        case .bottomHalf:        return rect(in: usable, x: 0...1, y: 0...0.5, gap: gap)
        case .topLeftQuarter:    return rect(in: usable, x: 0...0.5, y: 0.5...1, gap: gap)
        case .topRightQuarter:   return rect(in: usable, x: 0.5...1, y: 0.5...1, gap: gap)
        case .bottomLeftQuarter: return rect(in: usable, x: 0...0.5, y: 0...0.5, gap: gap)
        case .bottomRightQuarter: return rect(in: usable, x: 0.5...1, y: 0...0.5, gap: gap)
        case .center:
            // Keeps the window's size (clamped to the usable frame); no gaps. Unknown size falls back to usable.
            let w = current.width.isFinite && current.width > 0 ? min(current.width, usable.width) : usable.width
            let h = current.height.isFinite && current.height > 0 ? min(current.height, usable.height) : usable.height
            return CGRect(x: usable.midX - w / 2, y: usable.midY - h / 2, width: w, height: h)
        }
    }

    // MARK: - Private

    /// `floor(offset / (extent / count))` clamped to `0...count-1`. This is the rule SelectionEngine inlines;
    /// both must stay identical (shared fixture: 3840 wide, 5 columns, x = 1600 -> column 2).
    private static func slot(_ offset: Double, extent: Double, count: Int) -> Int {
        let n = max(count, 1)
        guard !offset.isNaN, extent > 0, extent.isFinite else { return 0 }
        let i = (offset / (extent / Double(n))).rounded(.down)
        return Int(min(max(i, 0), Double(n - 1)))
    }

    /// Sub-rectangle of `usable` given normalised ranges (y measured from the bottom). Every edge that does not
    /// lie on the usable frame's boundary (fraction 0 or 1) is pulled in by `gap / 2`.
    private static func rect(in usable: CGRect, x: ClosedRange<Double>, y: ClosedRange<Double>, gap: Double) -> CGRect {
        let h = max(gap, 0) / 2
        let left = x.lowerBound > 0 ? h : 0, right = x.upperBound < 1 ? h : 0
        let bottom = y.lowerBound > 0 ? h : 0, top = y.upperBound < 1 ? h : 0
        let w = usable.width, ht = usable.height
        return CGRect(
            x: usable.minX + x.lowerBound * w + left,
            y: usable.minY + y.lowerBound * ht + bottom,
            width: max(0, (x.upperBound - x.lowerBound) * w - left - right),
            height: max(0, (y.upperBound - y.lowerBound) * ht - bottom - top))
    }
}
