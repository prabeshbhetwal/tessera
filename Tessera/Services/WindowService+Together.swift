import AppKit
import TesseraCore

extension WindowService {
    /// Moves every window to its goal at once, so with a snap speed set they glide together, as one undo step: one
    /// ⌃⌥Z puts them all back. Returns where each landed, in `moves` order (nil when its app refused or a newer move
    /// took over), and the undo marker right after the moves. With `gap`, the windows beside one that landed off its
    /// goal follow it (see `follow`), so a fixed-size app such as System Settings leaves no hole in the group.
    func moveTogether(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double,
                      gap: Double? = nil) async -> (landed: [CGRect?], undoMarker: Int?) {
        let batch = newBatch()
        var landed = await applyAll(moves, primaryHeight: primaryHeight, duration: duration, batch: batch)
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
        await withTaskGroup(of: (Int, CGRect?).self) { group in
            for (index, move) in moves.enumerated() {
                group.addTask {
                    let result = await self.apply(move.goal, to: move.window, primaryHeight: primaryHeight,
                                                  crossingDisplays: false, duration: duration, batch: batch)
                    return (index, result.landed)  // nil when refused or taken over by a newer move
                }
            }
            var frames = [CGRect?](repeating: nil, count: moves.count)
            for await (index, frame) in group { frames[index] = frame }
            return frames
        }
    }
}

extension SettingsModel {
    /// Seconds a window takes to glide to a new frame: the snap speed, or 0 with Reduce Motion on.
    var glideSeconds: Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : settings.snapSeconds
    }
}
