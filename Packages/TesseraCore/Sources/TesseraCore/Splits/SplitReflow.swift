import CoreGraphics

/// When the person resizes or moves one window of a tiled group, the windows touching it follow its new edges so the
/// group still fills the display. Coordinates are AppKit orientation, as everywhere in `Splits`.
public enum SplitReflow {
    /// Smallest width or height a neighbour may be squeezed to, in points.
    public static let minimumSide: Double = 120
    /// Edges closer than this, in points, have not moved.
    private static let stillness: Double = 1
    /// Added to the gap when deciding whether two edges face each other.
    static let slack: Double = 8

    /// Every window's frame, in input order, once the one window that changed between `before` and `after` has pulled
    /// its neighbours along. An edge that moved drags the facing edge of the nearest windows beside it (sharing a band
    /// across the axis, however wide the space between), keeping `gap` between them, and that edge in turn drags the
    /// windows beside it, so a column seam moves as one. The changed window itself is never moved.
    ///
    /// Nil when not exactly one window changed, nothing faces the edges that moved, or a neighbour would end up smaller
    /// than `minimumSide` or stacked on another window: the arrangement is then left as the person made it.
    public static func frames(before: [CGRect], after: [CGRect], usable: CGRect, gap: Double) -> [CGRect]? {
        guard before.count == after.count, before.count > 1 else { return nil }
        let changed = before.indices.filter { i in
            Side.allCases.contains { abs($0.value(before[i]) - $0.value(after[i])) > stillness }
        }
        guard changed.count == 1, let anchor = changed.first else { return nil }
        let goal = after[anchor].intersection(usable)
        guard !goal.isNull, goal.width > 0, goal.height > 0 else { return nil }

        var result = before
        var queue = Side.allCases.compactMap { side -> Push? in
            let (from, to) = (side.value(before[anchor]), side.value(goal))
            return abs(from - to) > stillness ? Push(window: anchor, side: side, from: from, to: to) : nil
        }
        // (window, side) pairs already placed, as window * 4 + side; the changed window is never moved.
        var placed = Set(Side.allCases.map { anchor * 4 + $0.rawValue })
        while !queue.isEmpty {
            let push = queue.removeFirst()
            let facing = push.side.opposite
            // The nearest windows beyond the edge, however far: a hole (windows restored at login, or an earlier
            // adjustment nobody followed) would otherwise leave the seam dead for good, and the hole gets learned.
            // Every window beyond the edge counts as a blocker, placed ones (the anchor) included, so a push never
            // jumps over one; the seam keeps its tolerated-overlap width even when the nearest edge overlaps.
            let ahead = before.indices.filter { $0 != push.window }.compactMap { j -> (Int, Double)? in
                let space = push.side.isHigh ? facing.value(before[j]) - push.from : push.from - facing.value(before[j])
                guard space >= -SplitLearner.overlapTolerance,
                      push.side.across(before[push.window]).sharesBand(with: push.side.across(before[j])) else { return nil }
                return (j, space)
            }
            guard let nearest = ahead.map(\.1).min() else { continue }
            let cutoff = max(nearest, 0) + gap + slack
            for (j, space) in ahead where space <= cutoff && !placed.contains(j * 4 + facing.rawValue) {
                let edge = facing.value(before[j])
                let to = push.side.isHigh ? push.to + gap : push.to - gap
                guard facing.set(&result[j], to: to) >= minimumSide else { return nil }
                placed.insert(j * 4 + facing.rawValue)
                queue.append(Push(window: j, side: facing, from: edge, to: to))
            }
        }

        guard placed.count > Side.allCases.count else { return nil }  // nothing faced the edges that moved
        result[anchor] = goal
        guard !stacked(result) else { return nil }
        result[anchor] = after[anchor]
        return result
    }

    /// The goals once every window that landed off its goal (an app with a fixed or minimum size, such as System
    /// Settings) has pulled the windows beside it along, so no hole opens next to it. In input order; `landed` is nil
    /// for a window whose app refused the move. A window that landed off its goal keeps its goal here.
    public static func following(goals: [CGRect], landed: [CGRect?], gap: Double) -> [CGRect] {
        guard goals.count == landed.count else { return goals }
        let off = goals.indices.filter { i in
            guard let frame = landed[i] else { return false }
            return Side.allCases.contains { abs($0.value(frame) - $0.value(goals[i])) > stillness }
        }
        var current = goals
        for i in off {
            guard let frame = landed[i] else { continue }
            var after = current
            after[i] = frame
            current = frames(before: current, after: after, usable: .infinite, gap: gap) ?? after
        }
        for i in off { current[i] = goals[i] }
        return current
    }

    /// Two frames overlap by more than `SplitLearner.overlapTolerance` on both axes.
    static func stacked(_ frames: [CGRect]) -> Bool {
        frames.indices.contains { i in
            frames.indices.dropFirst(i + 1).contains { k in
                let (p, q) = (frames[i], frames[k])
                return min(p.maxX, q.maxX) - max(p.minX, q.minX) > SplitLearner.overlapTolerance
                    && min(p.maxY, q.maxY) - max(p.minY, q.minY) > SplitLearner.overlapTolerance
            }
        }
    }

    /// One edge that moved and still has to drag whatever faces it.
    private struct Push {
        let window: Int
        let side: Side
        let from: Double
        let to: Double
    }

    enum Side: Int, CaseIterable {
        case minX, maxX, minY, maxY

        var isHigh: Bool { self == .maxX || self == .maxY }
        private var isX: Bool { self == .minX || self == .maxX }

        var opposite: Side {
            switch self {
            case .minX: .maxX
            case .maxX: .minX
            case .minY: .maxY
            case .maxY: .minY
            }
        }

        func value(_ r: CGRect) -> Double {
            switch self {
            case .minX: r.minX
            case .maxX: r.maxX
            case .minY: r.minY
            case .maxY: r.maxY
            }
        }

        /// The rect's extent across the axis this side's edge moves along.
        func across(_ r: CGRect) -> Interval {
            isX ? Interval(lo: r.minY, hi: r.maxY) : Interval(lo: r.minX, hi: r.maxX)
        }

        /// Moves this edge of `r` to `to`, leaving the opposite edge where it is. Returns the new length along the axis,
        /// negative when the edge crossed the opposite one.
        func set(_ r: inout CGRect, to: Double) -> Double {
            let (lo, hi) = isHigh ? (opposite.value(r), to) : (to, opposite.value(r))
            r = isX
                ? CGRect(x: lo, y: r.minY, width: hi - lo, height: r.height)
                : CGRect(x: r.minX, y: lo, width: r.width, height: hi - lo)
            return hi - lo
        }
    }
}
