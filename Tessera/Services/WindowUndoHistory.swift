import CoreGraphics

/// `WindowService`'s undo state: a stack of earlier frames per window, and the chronological steps that say which
/// windows one ⌃⌥Z restores. Frames are AX coordinates, so undo needs no display geometry.
struct WindowUndoHistory {
    enum Key: Hashable {
        case window(CGWindowID)
        case element(Int)
    }

    private struct Stack {
        var ref: WindowRef
        var frames: [CGRect]
    }

    /// One undo step: usually one window, several for a batch (a Tile, or neighbours following a resize).
    private struct Step {
        var keys: [Key]
        let batch: Int?
    }

    private static let depth = 20
    private static let maxSteps = 500

    private var stacks: [Key: Stack] = [:]
    private var steps: [Step] = []
    private var nextBatch = 0

    /// A fresh tag for moves that should undo together; pass it to `push`, then `merge` once they are done.
    mutating func newBatch() -> Int {
        nextBatch += 1
        return nextBatch
    }

    /// Records `frame` as where `ref` was before a move, as its own step tagged `batch`.
    mutating func push(_ frame: CGRect, for ref: WindowRef, key: Key, batch: Int?) {
        var stack = stacks[key] ?? Stack(ref: ref, frames: [])
        stack.ref = ref
        stack.frames.append(frame)
        if stack.frames.count > Self.depth { stack.frames.removeFirst() }
        stacks[key] = stack
        steps.append(Step(keys: [key], batch: batch))
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
    }

    /// Joins every step tagged `batch` into one, where the latest of them sits. Only moves that recorded undo carry
    /// the tag, so other moves made meanwhile (a hotkey during a glide) stay steps of their own.
    mutating func merge(batch: Int) {
        let tagged = steps.indices.filter { steps[$0].batch == batch }
        guard let last = tagged.last, tagged.count > 1 else { return }
        steps[last].keys = tagged.flatMap { steps[$0].keys }
        for index in tagged.dropLast().reversed() { steps.remove(at: index) }
    }

    /// Takes the most recent step: each of its windows with the frame to restore. Windows whose stack has run dry are
    /// left out, so a step can come back empty. Nil when there are no steps left.
    mutating func popStep() -> [(key: Key, ref: WindowRef, frame: CGRect)]? {
        guard let step = steps.popLast() else { return nil }
        return step.keys.compactMap { key in
            guard var stack = stacks[key], let frame = stack.frames.popLast() else { return nil }
            stacks[key] = stack.frames.isEmpty ? nil : stack
            return (key, stack.ref, frame)
        }
    }
}
