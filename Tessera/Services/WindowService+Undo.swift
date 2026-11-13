import AppKit

/// ⌃⌥Z. Kept apart from `WindowService.swift` for its line limit.
extension WindowService {
    /// Undoes the step whose command started last: one move, or every window of a tile. When that command is still
    /// under way (gliding, or a Tile whose windows are still landing) it stops and goes back. Windows of apps in
    /// `excluding` (excluded after the move) are left alone. A step whose windows are all gone is dropped and the one
    /// before it tried; a step every live window refused is put back, so the next ⌃⌥Z can try again; a step held only
    /// by excluded apps is dropped and undo stops there, never reaching back to an older, unrelated step.
    func undoLast(excluding: Set<String> = []) -> UndoOutcome {
        var unfinished = takeUnfinishedMoves()
        while let step = unfinished ?? undo.popStep() {
            unfinished = nil
            if let outcome = restore(step.moves, order: step.order, excluding: excluding) { return outcome }
        }
        return .nothing
    }

    /// The latest command when it hasn't finished: a move still gliding, or a batch (a Tile) with moves still under way
    /// or not yet merged. Its moves stop and come back with what the batch already landed; the batch is cancelled so
    /// nothing more of it lands. Nil when the latest command is finished, so Undo pops the latest step instead.
    private func takeUnfinishedMoves() -> (moves: [WindowUndoHistory.Move], order: Int)? {
        let latestInFlight = inFlight.values.max { $0.order < $1.order }
        let batch: Int?
        let order: Int
        if let latestInFlight, latestInFlight.order >= undo.lastOrder {
            batch = latestInFlight.batch
            order = latestInFlight.order
        } else if let last = undo.lastBatch, let started = batchOrders[last] {
            batch = last
            order = started
        } else {
            return nil
        }
        if let batch { cancelledBatches.insert(batch) }
        // Landed moves first: a window moved twice in its batch goes back to where it began.
        var moves = batch.map { undo.takeBatch($0) } ?? []
        let stopping = inFlight.filter { batch != nil ? $0.value.batch == batch : $0.value.order == order }
        for (key, move) in stopping.sorted(by: { $0.value.generation < $1.value.generation }) {
            moves.append((key, move.window, move.before, Self.placement(move.before)))
            // Dropping its generation makes its glide or re-check stop (see `glide` and `apply`).
            generations[key] = nil
            glideStart[key] = nil
            inFlight[key] = nil
        }
        var seen = Set<UndoKey>()
        return (moves.filter { seen.insert($0.key).inserted }, order)
    }

    /// Puts each window of `moves` back. Nil when every window is gone, so the caller tries the step before.
    private func restore(_ moves: [WindowUndoHistory.Move], order: Int, excluding: Set<String>) -> UndoOutcome? {
        let displays = Self.currentDisplays()
        var restored = false
        var refused: WindowRef?
        var excluded = false
        for move in moves {
            if let id = move.ref.bundleID, excluding.contains(id) { excluded = true; continue }
            // A glide of this window still in flight would overwrite the restored frame on its next
            // tick; dropping its generation makes it stop (see `glide`).
            generations[move.key] = nil
            glideStart[move.key] = nil
            // Mapped onto a display that is still connected, so Undo never strands a window off screen.
            let frame = move.placement?.resolved(in: displays) ?? move.frame
            // Origin display unknown here, so use the cross-display order (safe on one display too).
            guard let error = setFrame(frame, on: move.ref, crossingDisplays: true) else { restored = true; continue }
            if refused == nil, !Self.isGone(move.ref, error: error) { refused = move.ref }
        }
        if restored { return .restored }
        if let refused {
            undo.reinstate(moves, order: order)
            return .refused(refused)
        }
        return excluded ? .nothing : nil
    }
}
