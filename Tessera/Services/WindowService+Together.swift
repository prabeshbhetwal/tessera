import AppKit

extension WindowService {
    /// Moves every window to its goal at once, so with a snap speed set they glide together, as one undo step: one
    /// ⌃⌥Z puts them all back. Returns where each landed, in `moves` order (nil when its app refused), and the undo
    /// marker right after the moves.
    func moveTogether(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double)
        async -> (landed: [CGRect?], undoMarker: Int?) {
        let ticket = WindowMutationScope.ticket ?? mutationContext.capture()
        return await WindowMutationScope.$ticket.withValue(ticket) {
            await moveTogetherScoped(moves, primaryHeight: primaryHeight, duration: duration)
        }
    }

    private func moveTogetherScoped(_ moves: [(window: WindowRef, goal: CGRect)], primaryHeight: CGFloat, duration: Double)
        async -> (landed: [CGRect?], undoMarker: Int?) {
        let batch = newBatch()
        let landed = await withTaskGroup(of: (Int, CGRect?).self) { group in
            for (index, move) in moves.enumerated() {
                group.addTask {
                    let result = await self.apply(move.goal, to: move.window, primaryHeight: primaryHeight,
                                                  crossingDisplays: false, duration: duration, batch: batch)
                    if case let .applied(frame) = result { return (index, frame) }
                    return (index, nil)
                }
            }
            var frames = [CGRect?](repeating: nil, count: moves.count)
            for await (index, frame) in group { frames[index] = frame }
            return frames
        }
        return (landed, mergeMoves(batch))
    }
}

extension SettingsModel {
    /// Seconds a window takes to glide to a new frame: the snap speed, or 0 with Reduce Motion on.
    var glideSeconds: Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : settings.snapSeconds
    }
}
