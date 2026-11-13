import AppKit

/// ⌃⌥Z. Kept apart from `WindowService.swift` for its line limit.
extension WindowService {
    /// Undoes the most recent step: one move, or every window of a tile. A move still under way (gliding, or a Tile
    /// whose windows are still landing) counts as the most recent: it stops and goes back. Windows of apps in
    /// `excluding` (excluded after the move) are left alone. A step whose windows are all gone is dropped and the one
    /// before it tried; a step every live window refused is put back, so the next ⌃⌥Z can try again; a step held only
    /// by excluded apps is dropped and undo stops there, never reaching back to an older, unrelated step.
    func undoLast(excluding: Set<String> = []) -> UndoOutcome {
        var unfinished = takeUnfinishedMoves()
        while let moves = unfinished ?? undo.popStep() {
            unfinished = nil
            if let outcome = restore(moves, excluding: excluding) { return outcome }
        }
        return .nothing
    }

    /// Moves still under way, plus what their batches (a Tile in progress) already landed; their batches are cancelled
    /// so nothing more of them lands. Nil when nothing is under way, so Undo takes the latest finished step instead.
    private func takeUnfinishedMoves() -> [WindowUndoHistory.Move]? {
        var batches = Set(inFlight.values.compactMap(\.batch))
        if let last = undo.lastBatch, openBatches.contains(last) { batches.insert(last) }
        guard !inFlight.isEmpty || !batches.isEmpty else { return nil }
        cancelledBatches.formUnion(batches)
        // Landed moves first: a window moved twice in its batch goes back to where it began.
        var moves = batches.sorted().flatMap { undo.takeBatch($0) }
        for (key, move) in inFlight.sorted(by: { $0.value.generation < $1.value.generation }) {
            moves.append((key, move.window, move.before, Self.placement(move.before)))
        }
        // Dropping each generation makes its glide or re-check stop (see `glide` and `apply`).
        for key in inFlight.keys { generations[key] = nil; glideStart[key] = nil }
        inFlight = [:]
        var seen = Set<UndoKey>()
        return moves.filter { seen.insert($0.key).inserted }
    }

    /// Puts each window of `moves` back. Nil when every window is gone, so the caller tries the step before.
    private func restore(_ moves: [WindowUndoHistory.Move], excluding: Set<String>) -> UndoOutcome? {
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
            undo.reinstate(moves)
            return .refused(refused)
        }
        return excluded ? .nothing : nil
    }
}
