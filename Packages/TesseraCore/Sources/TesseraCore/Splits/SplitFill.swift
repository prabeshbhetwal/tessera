import CoreGraphics

/// When a window of a tiled group closes, the windows beside the space it leaves grow into it, so the display stays
/// covered. Coordinates are AppKit orientation, as everywhere in `Splits`.
public enum SplitFill {
    /// Every window's frame, in input order, once the windows on one side of `hole` (the closed window's frame) have
    /// grown across it. `frames` are the windows left on the display, most recently used first: of the sides whose
    /// windows can cover the hole, the one holding the most recently used window wins. A side can cover the hole when
    /// the windows facing it (within `gap` plus a little) all sit within the hole's extent across the axis and
    /// together span it, as one window beside a closed one, or a column of windows beside a closed column.
    ///
    /// Nil when no side can cover the hole without stacking windows: the windows are then left where they are.
    public static func frames(filling hole: CGRect, frames: [CGRect], gap: Double) -> [CGRect]? {
        let reach = gap + SplitReflow.slack
        var best: (rank: Int, frames: [CGRect])?
        for side in SplitReflow.Side.allCases {
            let facing = side.opposite  // the neighbours' edge that faces the hole
            let span = side.across(hole)
            let beside = frames.indices.filter { j in
                let edge = facing.value(frames[j])
                let space = side.isHigh ? edge - side.value(hole) : side.value(hole) - edge
                return space >= -SplitLearner.overlapTolerance && space <= reach
                    && span.overlap(side.across(frames[j])) > SplitLearner.overlapTolerance
            }
            guard let rank = beside.min(), rank < best?.rank ?? .max else { continue }
            let extents: [Interval] = beside.map { side.across(frames[$0]) }
            let within = extents.allSatisfy { $0.lo >= span.lo - reach && $0.hi <= span.hi + reach }
            let lo: Double = extents.map { $0.lo }.min() ?? .infinity
            let hi: Double = extents.map { $0.hi }.max() ?? -.infinity
            guard within, lo <= span.lo + reach, hi >= span.hi - reach else { continue }
            var result = frames
            for j in beside { _ = facing.set(&result[j], to: facing.value(hole)) }
            guard !SplitReflow.stacked(result) else { continue }
            best = (rank, result)
        }
        return best?.frames
    }

    /// `frames` once every hole in `holes` that some side can cover is filled. A hole nothing faces yet is tried again
    /// after another fills, so adjacent closed windows (an app quitting with two columns) are covered in any order.
    /// Nil when none could be filled.
    public static func frames(filling holes: [CGRect], frames: [CGRect], gap: Double) -> [CGRect]? {
        var result = frames
        var open = holes
        while !open.isEmpty {
            let before = open.count
            open.removeAll { hole in
                guard let next = Self.frames(filling: hole, frames: result, gap: gap) else { return false }
                result = next
                return true
            }
            if open.count == before { break }  // no progress: what is left can't be covered
        }
        return open.count < holes.count ? result : nil
    }
}
