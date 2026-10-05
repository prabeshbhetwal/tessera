import CoreGraphics
import Foundation

public enum SplitRejection: Error, Equatable {
    case noWindows
    case overlap

    public var message: String {
        switch self {
        case .noWindows: "No windows on this display"
        case .overlap: "Windows overlap, so there's no split to remember"
        }
    }
}

/// Turns the frames of the windows on one display into slots: each window's rectangle as fractions of `usable`.
public enum SplitLearner {
    /// Overlap, in points, that still counts as two windows side by side. More than this on both axes is a stack.
    public static let overlapTolerance: Double = 24
    /// Added to the profile gap to decide how sloppy an edge or gap may be and still snap.
    private static let snapSlack: Double = 8

    /// Slots come back in reading order. Coordinates are AppKit orientation, as in `UnitRect`.
    public static func learn(_ windows: [(bundleID: String?, frame: CGRect)], usable: CGRect, gap: Double)
        -> Result<[Slot], SplitRejection> {
        guard !windows.isEmpty else { return .failure(.noWindows) }
        let clipped = windows.map { $0.frame.intersection(usable) }
        // Callers only pass windows whose centre is on this display, so a window wholly outside `usable` is not a
        // real case. Rejecting keeps the slot count equal to the window count and every slot a positive size.
        guard clipped.allSatisfy({ !$0.isNull && $0.width > 0 && $0.height > 0 }) else { return .failure(.noWindows) }

        var boxes = clipped.map(Box.init)
        let stacked = boxes.indices.contains { i in
            boxes.indices.dropFirst(i + 1).contains { j in
                boxes[i].x.overlap(boxes[j].x) > overlapTolerance && boxes[i].y.overlap(boxes[j].y) > overlapTolerance
            }
        }
        if stacked { return .failure(.overlap) }

        let bounds = Box(usable)
        let reach = gap + snapSlack
        for i in boxes.indices {
            boxes[i].x.snap(to: bounds.x, within: reach)
            boxes[i].y.snap(to: bounds.y, within: reach)
        }
        let settled = settleGaps(settleGaps(boxes, along: \.x, across: \.y, gap: gap), along: \.y, across: \.x, gap: gap)
        if settled.allSatisfy(\.hasArea) { boxes = settled }  // tiny windows between big gaps: keep the raw edges

        let frames = boxes.map(\.rect)
        return .success(readingOrder(frames).map { index in
            Slot(bundleID: windows[index].bundleID ?? SplitKey.unknownApp, rect: UnitRect(frames[index], in: usable))
        })
    }

    /// Indices in reading order: top row first, left to right. Two rects share a row when their vertical overlap
    /// exceeds half the smaller height; a tall window therefore leads the stacked windows beside it.
    public static func readingOrder(_ rects: [CGRect]) -> [Int] {
        let boxes = rects.map(Box.init)
        let topFirst = rects.indices.sorted { a, b in
            if rects[a].maxY != rects[b].maxY { return rects[a].maxY > rects[b].maxY }
            if rects[a].minX != rects[b].minX { return rects[a].minX < rects[b].minX }
            return a < b
        }
        var rows: [[Int]] = []
        for index in topFirst {
            if let row = rows.firstIndex(where: { boxes[$0[0]].y.sharesBand(with: boxes[index].y) }) {
                rows[row].append(index)
            } else {
                rows.append([index])
            }
        }
        return rows.flatMap { row in
            row.sorted { a, b in
                if rects[a].minX != rects[b].minX { return rects[a].minX < rects[b].minX }
                if rects[a].maxY != rects[b].maxY { return rects[a].maxY > rects[b].maxY }
                return a < b
            }
        }
    }

    /// Resets the space between windows that sit one after the other along `axis` and share a band `across` it
    /// (only spaces from 0 up to `gap + snapSlack`; small overlaps are left as they are). Edges that face each other,
    /// directly or through a neighbour, form a group. The group's edges are put `gap` apart around the middle of the
    /// group's extent, so every window across the same seam gets exactly `gap` and input order cannot matter.
    private static func settleGaps(_ boxes: [Box], along axis: WritableKeyPath<Box, Interval>,
                                   across: KeyPath<Box, Interval>, gap: Double) -> [Box] {
        // Edge ids: 2i is the low edge of box i, 2i + 1 its high edge. `parent` is a union-find over facing edges.
        var parent = Array(0..<(2 * boxes.count))
        func root(_ edge: Int) -> Int {
            var edge = edge
            while parent[edge] != edge { edge = parent[edge] }
            return edge
        }
        func position(_ edge: Int) -> Double {
            edge.isMultiple(of: 2) ? boxes[edge / 2][keyPath: axis].lo : boxes[edge / 2][keyPath: axis].hi
        }
        var facing = Set<Int>()
        for i in boxes.indices {
            for j in boxes.indices where i != j {
                let space = boxes[j][keyPath: axis].lo - boxes[i][keyPath: axis].hi
                guard space >= 0, space <= gap + snapSlack,
                      boxes[i][keyPath: across].sharesBand(with: boxes[j][keyPath: across]) else { continue }
                parent[root(2 * i + 1)] = root(2 * j)
                facing.formUnion([2 * i + 1, 2 * j])
            }
        }
        var extent: [Int: (lo: Double, hi: Double)] = [:]
        for edge in facing {
            let (group, at) = (root(edge), position(edge))
            extent[group] = (min(extent[group]?.lo ?? at, at), max(extent[group]?.hi ?? at, at))
        }
        var result = boxes
        for edge in facing {
            guard let seam = extent[root(edge)] else { continue }
            let middle = (seam.lo + seam.hi) / 2
            if edge.isMultiple(of: 2) {
                result[edge / 2][keyPath: axis].lo = middle + gap / 2
            } else {
                result[edge / 2][keyPath: axis].hi = middle - gap / 2
            }
        }
        return result
    }
}

private struct Interval {
    var lo: Double
    var hi: Double

    var length: Double { hi - lo }

    func overlap(_ other: Interval) -> Double { min(hi, other.hi) - max(lo, other.lo) }

    func sharesBand(with other: Interval) -> Bool { overlap(other) > min(length, other.length) / 2 }

    /// Moves an end onto the matching end of `bounds` when it is within `reach` of it.
    mutating func snap(to bounds: Interval, within reach: Double) {
        if abs(lo - bounds.lo) <= reach { lo = bounds.lo }
        if abs(hi - bounds.hi) <= reach { hi = bounds.hi }
    }
}

private struct Box {
    var x: Interval
    var y: Interval

    init(_ rect: CGRect) {
        x = Interval(lo: rect.minX, hi: rect.maxX)
        y = Interval(lo: rect.minY, hi: rect.maxY)
    }

    var hasArea: Bool { x.length > 0 && y.length > 0 }
    var rect: CGRect { CGRect(x: x.lo, y: y.lo, width: x.length, height: y.length) }
}
