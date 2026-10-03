import Foundation

/// Decides which step of a named cycle to run (M2 spec §4).
///
/// A repeat of the same cycle on the same window within `timeout` seconds of the previous press
/// advances to the next step (wrapping); anything else restarts at step 0. A caller that skips a
/// step that would not change the window just calls `step` again with the same `now`.
public struct CycleTracker: Sendable {
    private struct Last: Sendable {
        let cycle: String
        let windowKey: String
        let index: Int
        let time: Date
    }

    public let timeout: TimeInterval
    private var last: Last?

    public init(timeout: TimeInterval = 2) { self.timeout = timeout }

    /// Returns the step index in `0..<stepCount`, or 0 when `stepCount < 1`.
    public mutating func step(cycle: String, windowKey: String, stepCount: Int, now: Date) -> Int {
        guard stepCount > 0 else {
            last = nil
            return 0
        }
        var index = 0
        if let l = last, l.cycle == cycle, l.windowKey == windowKey {
            let elapsed = now.timeIntervalSince(l.time)
            if elapsed >= 0, elapsed <= timeout { index = (l.index + 1) % stepCount }
        }
        last = Last(cycle: cycle, windowKey: windowKey, index: index, time: now)
        return index
    }
}
