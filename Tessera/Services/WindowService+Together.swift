import AppKit
import TesseraCore

extension WindowService {
    /// Moves every window to its goal at once, so with a snap speed set they glide together, as one undo step: one
    /// ⌃⌥Z puts them all back. Returns where each landed, in `moves` order (nil when its app refused or a newer move
    /// took over), and the undo marker right after the moves. With `gap`, the windows beside one that landed off its
    /// goal follow it (see `follow`), so a fixed-size app such as System Settings leaves no hole in the group. Every
    /// move runs under one mutation ticket, so a display or Space change stops the rest of the group. The moves at
    /// `retrying` are asked twice more when refused (a window still loading), inside the same undo step. With
    /// `undoingIfRefused` (each window's frame before), a move whose `retrying` windows all still refuse puts the
    /// others back there in the same step and reports nothing landed.
    func moveTogether(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double,
                      gap: Double? = nil, retrying: Set<Int> = [], undoingIfRefused: [CGRect]? = nil)
        async -> (landed: [CGRect?], undoMarker: Int?) {
        let ticket = WindowMutationScope.ticket ?? mutationContext.capture()
        return await WindowMutationScope.$ticket.withValue(ticket) {
            await moveTogetherScoped(moves, primaryHeight: primaryHeight, duration: duration, gap: gap, retrying: retrying,
                                     undoingIfRefused: undoingIfRefused)
        }
    }

    private func moveTogetherScoped(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double,
                                    gap: Double?, retrying: Set<Int>, undoingIfRefused: [CGRect]?)
        async -> (landed: [CGRect?], undoMarker: Int?) {
        let batch = newBatch()
        var results = await applyResults(moves, primaryHeight: primaryHeight, duration: duration, batch: batch)
        for _ in 0..<2 {
            // Only a refusal is asked again: a move a newer one took over, or Undo cancelled, stays theirs.
            var refused = retrying.filter { index in
                guard results.indices.contains(index), case .failed = results[index] else { return false }
                return true
            }.sorted()
            guard !refused.isEmpty, !Task.isCancelled, (try? await Task.sleep(for: .milliseconds(400))) != nil else { break }
            // A window gone unreadable, or dragged to another display during the pause, is not pulled back.
            let topology = (WindowMutationScope.ticket ?? mutationContext.capture()).topology
            refused = refused.filter { index in
                guard let now = frame(of: moves[index].window) else { return false }
                let here = { (r: CGRect) in topology.key(containing: CoordinateSpace.toAX(r, primaryHeight: topology.primaryHeight)) }
                return here(now) == here(moves[index].goal)
            }
            guard !refused.isEmpty else { break }
            let again = await applyResults(refused.map { moves[$0] }, primaryHeight: primaryHeight, duration: duration, batch: batch)
            for (index, result) in zip(refused, again) { results[index] = result }
        }
        var landed = results.map(\.landed)
        if let before = undoingIfRefused, !retrying.isEmpty, before.count == moves.count,
           retrying.allSatisfy({ !moves.indices.contains($0) || landed[$0] == nil }) {
            // Only windows still where this move left them: one the user dragged meanwhile stays where they put it.
            let back = moves.indices.filter { index in
                guard let there = landed[index], let now = frame(of: moves[index].window) else { return false }
                return now.insetBy(dx: -2, dy: -2).contains(there) && there.insetBy(dx: -2, dy: -2).contains(now)
            }
            let returned = await applyResults(back.map { (window: moves[$0].window, goal: before[$0]) },
                                              primaryHeight: primaryHeight, duration: duration, batch: batch)
            // Everything is verifiably back where it was: no undo step is left for a move that, in effect, never
            // happened. A window that refused to go back keeps its ⌃⌥Z.
            let allBack = zip(back, returned).allSatisfy { index, result in
                result.landed.map { abs($0.minX - before[index].minX) <= 2 && abs($0.minY - before[index].minY) <= 2
                    && abs($0.width - before[index].width) <= 2 && abs($0.height - before[index].height) <= 2 } ?? false
            }
            if allBack, back.count == moves.indices.filter({ landed[$0] != nil }).count {
                _ = undo.takeBatch(batch)
                batchOrders[batch] = nil
                cancelledBatches.remove(batch)
                return ([CGRect?](repeating: nil, count: moves.count), nil)
            }
            return ([CGRect?](repeating: nil, count: moves.count), mergeMoves(batch))
        }
        if let gap {
            landed = await follow(moves, landed: landed, gap: gap, primaryHeight: primaryHeight, duration: duration,
                                  batch: batch)
        }
        return (landed, mergeMoves(batch))
    }

    /// Moves the windows beside any that landed off its goal (an app with a fixed or minimum size) to meet its real
    /// edges, keeping `gap`, as part of `batch` (`SplitReflow.following`). Returns `landed` with their new frames.
    func follow(_ moves: [(window: WindowRef, goal: CGRect)], landed: [CGRect?], gap: Double, primaryHeight: CGFloat,
                duration: Double, batch: Int) async -> [CGRect?] {
        let goals = moves.map(\.goal)
        let followed = SplitReflow.following(goals: goals, landed: landed, gap: gap)
        let again = moves.indices.filter { landed[$0] != nil && !followed[$0].equalTo(goals[$0]) }
        guard !again.isEmpty else { return landed }
        let refreshed = await applyAll(again.map { (window: moves[$0].window, goal: followed[$0]) },
                                       primaryHeight: primaryHeight, duration: duration, batch: batch)
        var result = landed
        for (index, frame) in zip(again, refreshed) where frame != nil { result[index] = frame }
        return result
    }

    private func applyAll(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double,
                          batch: Int) async -> [CGRect?] {
        await applyResults(moves, primaryHeight: primaryHeight, duration: duration, batch: batch).map(\.landed)
    }

    private func applyResults(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double,
                              batch: Int) async -> [ApplyResult] {
        await withTaskGroup(of: (Int, ApplyResult).self) { group in
            for (index, move) in moves.enumerated() {
                group.addTask {
                    (index, await self.apply(move.goal, to: move.window, primaryHeight: primaryHeight,
                                             crossingDisplays: false, duration: duration, batch: batch))
                }
            }
            var results = [ApplyResult](repeating: .superseded, count: moves.count)
            for await (index, result) in group { results[index] = result }
            return results
        }
    }
}

extension SettingsModel {
    /// Seconds a window takes to glide to a new frame: the snap speed, or 0 with Reduce Motion on.
    var glideSeconds: Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : settings.snapSeconds
    }
}
