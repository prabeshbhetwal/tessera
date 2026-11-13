import AppKit

extension WindowService {
    /// Undoes the most recent step: one move, or every window of a tile. False when there is nothing to undo.
    func undoLast() -> Bool {
        let ticket = WindowMutationScope.ticket ?? mutationContext.capture()
        let valid = { [mutationContext] in !Task.isCancelled && mutationContext.isCurrent(ticket, on: ticket.topology.keys, refreshSpaces: true) }
        guard valid() else { return false }
        if let latest = inFlight.values.max(by: { $0.order < $1.order }), latest.order >= undo.lastOrder {
            let pending = inFlight.filter { $0.value.generation == latest.generation
                || (latest.batch != nil && $0.value.batch == latest.batch) }
            var completed: [WindowUndoHistory.Move] = []
            if let batch = latest.batch {
                cancelPendingBatch(batch)
                completed = undo.takeBatch(batch)
            }
            var restored = false
            for (key, move) in pending {
                generations[key] = nil
                glideStart[key] = nil
                inFlight[key] = nil
                let goal = Self.recoveredUndoFrame(move.before, placement: move.placement, topology: ticket.topology)
                if setFrame(goal, on: move.window, crossingDisplays: true, valid: valid),
                   let actual = readFrame(move.window), Self.matches(actual, goal) { rememberPlacement(actual, of: move.window); restored = true }
                else { undo.push(move.before, for: move.window, key: key, batch: move.batch, order: move.order, placement: move.placement) }
            }
            for (key, ref, frame, placement) in completed {
                let goal = Self.recoveredUndoFrame(frame, placement: placement, topology: ticket.topology)
                if setFrame(goal, on: ref, crossingDisplays: true, valid: valid), let actual = readFrame(ref), Self.matches(actual, goal) {
                    rememberPlacement(actual, of: ref)
                    restored = true
                } else { undo.push(frame, for: ref, key: key, batch: latest.batch, order: latest.order, placement: placement) }
            }
            return restored
        }
        while undo.lastOrder >= 0 {
            let order = undo.lastOrder
            if let batch = undo.lastBatch { cancelPendingBatch(batch) }
            guard let step = undo.popStep() else { break }
            var restored = false
            var retry: [WindowUndoHistory.Move] = []
            for (key, ref, frame, placement) in step {
                generations[key] = nil
                glideStart[key] = nil
                guard NSRunningApplication(processIdentifier: ref.pid)?.isTerminated == false,
                      AX.isValid(ref.element) else { continue }
                let goal = Self.recoveredUndoFrame(frame, placement: placement, topology: ticket.topology)
                if setFrame(goal, on: ref, crossingDisplays: true, valid: valid), let actual = readFrame(ref),
                   Self.matches(actual, goal) { rememberPlacement(actual, of: ref); restored = true }
                else { retry.append((key, ref, frame, placement)) }
            }
            if !retry.isEmpty { undo.restoreStep(retry, order: order); return restored }
            if restored { return true }
        }
        return false
    }

}
