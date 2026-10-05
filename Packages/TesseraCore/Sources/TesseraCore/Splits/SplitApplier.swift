import CoreGraphics

/// Turns a learned split plus the windows now on a display into target frames.
public enum SplitApplier {
    /// One frame per window, in input order; nil when the windows' apps are not the split's apps (the caller then
    /// falls back to equal tiles).
    ///
    /// Each window takes a slot of its app. A split that is one row, or one column on `portrait`, is packed along that
    /// axis: windows go in their current order, each taking its slot's size, and the learned gaps are laid between them
    /// as `gapPlacement` says; a window that would end up past either end of the usable frame slides back inside.
    /// Duplicates then pair along the axis too (the leftmost Chrome takes the leftmost Chrome slot). Any other split,
    /// or `restoresOrder`, puts every window in its own slot, duplicates pairing in reading order.
    public static func frames(for split: LearnedSplit, windows: [(bundleID: String?, frame: CGRect)], usable: CGRect,
                              portrait: Bool, restoresOrder: Bool, gapPlacement: SplitGapPlacement) -> [CGRect]? {
        let axis = Axis(portrait: portrait)
        let slots = split.slots.map(\.rect)
        let current = windows.map(\.frame)
        guard !restoresOrder, axis.isSingleLine(slots) else {
            let slotOf = pair(windows, in: SplitLearner.readingOrder(current), with: split.slots, in: Array(slots.indices))
            return slotOf?.map { slots[$0].absolute(in: usable) }
        }

        // Learned gaps along the axis: before the first slot, between neighbours, and after the last (index slots.count).
        let learned = slots.indices.sorted { a, b in
            let (p, q) = (axis.along(slots[a]).lo, axis.along(slots[b]).lo)
            return p != q ? p < q : a < b
        }
        let order = axis.currentOrder(current)
        guard let slotOf = pair(windows, in: order, with: split.slots, in: learned) else { return nil }
        var rank = [Int](repeating: 0, count: slots.count)
        var gaps: [Double] = []
        var edge = 0.0
        for (position, slot) in learned.enumerated() {
            rank[slot] = position
            gaps.append(axis.along(slots[slot]).lo - edge)
            edge = axis.along(slots[slot]).hi
        }
        gaps.append(1 - edge)

        var frames = [CGRect](repeating: .zero, count: windows.count)
        var cursor = 0.0
        for (index, window) in order.enumerated() {
            let slot = slotOf[window]
            let (lead, trail) = switch gapPlacement {
            case .staysInPlace: (gaps[index], 0.0)
            case .followsNeighbour: (rank[slot] == 0 ? gaps[0] : 0.0, gaps[rank[slot] + 1])
            }
            let size = axis.along(slots[slot]).length
            let span = Interval(lo: cursor + lead, hi: cursor + lead + size)
            // A negative learned gap (slots that overlapped) can carry a window past an end of the line. Slide it back
            // inside, which brings back at most the overlap that was learned.
            frames[window] = axis.rect(along: span.insideUnit, like: slots[slot]).absolute(in: usable)
            cursor = span.hi + trail
        }
        return frames
    }

    /// For each window, the index of the slot it takes; nil when the apps differ. Taking windows in `windowOrder`,
    /// each takes the first of its app's slots still open in `slotOrder`.
    private static func pair(_ windows: [(bundleID: String?, frame: CGRect)], in windowOrder: [Int],
                             with slots: [Slot], in slotOrder: [Int]) -> [Int]? {
        guard windows.count == slots.count else { return nil }
        var open = Dictionary(grouping: slotOrder, by: { slots[$0].bundleID })
        var slotOf = [Int](repeating: 0, count: windows.count)
        for window in windowOrder {
            let app = windows[window].bundleID ?? SplitKey.unknownApp
            guard var queue = open[app], !queue.isEmpty else { return nil }
            slotOf[window] = queue.removeFirst()
            open[app] = queue
        }
        return slotOf
    }
}

private extension Interval {
    /// This span slid, keeping its length, to lie within 0…1. The start wins if the span is longer than that.
    var insideUnit: Interval {
        let lo = max(0, min(self.lo, 1 - length))
        return Interval(lo: lo, hi: lo + length)
    }
}

/// The axis a split is packed along: x for a row, and y read from the top for a column on a portrait display.
private struct Axis {
    let portrait: Bool

    func along(_ r: UnitRect) -> Interval {
        portrait ? Interval(lo: 1 - (r.y + r.height), hi: 1 - r.y) : Interval(lo: r.x, hi: r.x + r.width)
    }

    func across(_ r: UnitRect) -> Interval {
        portrait ? Interval(lo: r.x, hi: r.x + r.width) : Interval(lo: r.y, hi: r.y + r.height)
    }

    /// `r` moved and resized along the axis; its extent across the axis is kept.
    func rect(along span: Interval, like r: UnitRect) -> UnitRect {
        portrait
            ? UnitRect(x: r.x, y: 1 - span.hi, width: r.width, height: span.length)
            : UnitRect(x: span.lo, y: r.y, width: span.length, height: r.height)
    }

    /// Every pair of slots shares a band across the axis, so the slots sit one after another along it.
    func isSingleLine(_ slots: [UnitRect]) -> Bool {
        slots.indices.allSatisfy { i in
            slots.indices.dropFirst(i + 1).allSatisfy { across(slots[i]).sharesBand(with: across(slots[$0])) }
        }
    }

    /// Window indices in current order along the axis: left to right, or top first on `portrait`.
    func currentOrder(_ frames: [CGRect]) -> [Int] {
        frames.indices.sorted { a, b in
            let (p, q) = (frames[a], frames[b])
            if portrait {
                if p.maxY != q.maxY { return p.maxY > q.maxY }
                if p.minX != q.minX { return p.minX < q.minX }
            } else {
                if p.minX != q.minX { return p.minX < q.minX }
                if p.minY != q.minY { return p.minY > q.minY }
            }
            return a < b
        }
    }
}
