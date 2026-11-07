import CoreGraphics

/// `WindowService`'s undo state: chronological steps, each holding the windows one ⌃⌥Z restores and the frame each
/// had before its move. Frames are AX coordinates, so undo needs no display geometry.
struct WindowUndoHistory {
    enum Key: Hashable {
        case window(CGWindowID)
        case element(Int)
    }

    typealias Move = (key: Key, ref: WindowRef, frame: CGRect)

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
    mutating func push(_ frame: CGRect, for ref: WindowRef, key: Key, batch: Int?) {
        marker += 1
        steps.append(Step(moves: [(key, ref, frame)], batch: batch))
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
            steps[first].moves += joined.flatMap { steps[$0].moves }
            for index in joined.reversed() { steps.remove(at: index) }
            marker += 1
        }
        return first == steps.count - 1 ? marker : nil
    }

    /// Takes the most recent step: each of its windows with the frame to restore. Nil when there are no steps left.
    mutating func popStep() -> [Move]? {
        guard let step = steps.popLast() else { return nil }
        marker += 1
        return step.moves
    }
}
