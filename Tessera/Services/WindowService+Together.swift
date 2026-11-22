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
        // A required window (the newcomer) that still refuses: the rest goes back in this same step, since a group with
        // an unfilled slot is never accepted.
        if let before = undoingIfRefused, before.count == moves.count,
           retrying.contains(where: { moves.indices.contains($0) && landed[$0] == nil }) {
            // Every window not where it began, except one the user dragged since this move left it: put it back. A
            // newcomer that moved part way before failing is asked back too.
            let back = moves.indices.filter { index in
                guard let now = frame(of: moves[index].window), !Self.near(now, before[index]) else { return false }
                if let there = landed[index] { return Self.near(now, there) }
                return retrying.contains(index)
            }
            _ = await applyResults(back.map { (window: moves[$0].window, goal: before[$0]) },
                                   primaryHeight: primaryHeight, duration: duration, batch: batch)
            // The undo step goes only when every window is verifiably where it began; otherwise ⌃⌥Z keeps it.
            let allBack = moves.indices.allSatisfy { index in frame(of: moves[index].window).map { Self.near($0, before[index]) } ?? false }
            if allBack {
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

    /// Same frame within 2 pt (apps round to whole points).
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
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
