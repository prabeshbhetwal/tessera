import CoreGraphics
import TesseraCore

/// `WindowService`'s undo state: chronological steps, each holding the windows one ⌃⌥Z restores and the frame each
/// had before its move. Frames are AX coordinates; each also notes its display, so Undo can map it onto a display
/// that is still connected.
struct WindowUndoHistory {
    enum Key: Hashable {
        case window(CGWindowID)
        case element(Int)
    }

    typealias Move = (key: Key, ref: WindowRef, frame: CGRect, placement: WindowPlacementSnapshot?)

    /// One undo step: usually one window, several for a batch (a Tile, or neighbours following a resize).
    private struct Step {
        var moves: [Move]
        let batch: Int?
    }

    private static let maxSteps = 500

    private var steps: [Step] = []
    private var nextBatch = 0
    /// Bumped whenever the steps change (a push, a merge that joins steps, a pop), so a caller can tell whether the
    /// latest step is still the one it saw.
    private(set) var marker = 0

    /// A fresh tag for moves that should undo together; pass it to `push`, then `merge` once they are done.
    mutating func newBatch() -> Int {
        nextBatch += 1
        return nextBatch
    }

    /// Records `frame` as where `ref` was before a move, as its own step tagged `batch`.
    mutating func push(_ frame: CGRect, for ref: WindowRef, key: Key, batch: Int?,
                       placement: WindowPlacementSnapshot? = nil) {
        marker += 1
        steps.append(Step(moves: [(key, ref, frame, placement)], batch: batch))
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
    }

    /// Joins the steps tagged `batch` into the first of them. A tagged step for a window that another step moved in
    /// the meantime (a hotkey during a glide) stays separate, so every window still undoes in the order it moved.
    /// Returns `marker` when the merged step is the latest in the history, so the next undo takes back exactly this
    /// batch; nil when no step carries `batch` (every move failed) or another step came after it.
    @discardableResult
    mutating func merge(batch: Int) -> Int? {
        guard let first = steps.firstIndex(where: { $0.batch == batch }) else { return nil }
        var movedSince = Set<Key>()
        var joined: [Int] = []
        for index in steps.indices.dropFirst(first + 1) {
            let keys = Set(steps[index].moves.map(\.key))
            if steps[index].batch == batch, movedSince.isDisjoint(with: keys) {
                joined.append(index)
            } else {
                movedSince.formUnion(keys)
            }
        }
        if !joined.isEmpty {
            // A window moved twice in the batch (it followed a neighbour that landed short) undoes to where it began.
            var seen = Set(steps[first].moves.map(\.key))
            steps[first].moves += joined.flatMap { steps[$0].moves }.filter { seen.insert($0.key).inserted }
            for index in joined.reversed() { steps.remove(at: index) }
            marker += 1
        }
        return first == steps.count - 1 ? marker : nil
    }

    /// The batch tag of the latest step, while its moves are still separate steps (before `merge`).
    var lastBatch: Int? { steps.last?.batch }

    /// Removes every step tagged `batch` and returns their moves, oldest first: a batch Undo cancelled midway.
    mutating func takeBatch(_ batch: Int) -> [Move] {
        let moves = steps.filter { $0.batch == batch }.flatMap(\.moves)
        steps.removeAll { $0.batch == batch }
        if !moves.isEmpty { marker += 1 }
        return moves
    }

    /// Takes the most recent step: each of its windows with the frame to restore. Nil when there are no steps left.
    mutating func popStep() -> [Move]? {
        guard let step = steps.popLast() else { return nil }
        marker += 1
        return step.moves
    }

    /// Puts back a step `popStep` took when none of it could be restored, as the latest step again.
    mutating func reinstate(_ moves: [Move]) {
        marker += 1
        steps.append(Step(moves: moves, batch: nil))
    }
}
