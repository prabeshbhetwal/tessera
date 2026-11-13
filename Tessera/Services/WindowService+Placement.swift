import AppKit
import ApplicationServices

/// Writing frames: the exact write and the glide toward it. Kept apart from `WindowService.swift` for its line limit.
extension WindowService {
    /// Writes an AX frame with Enhanced UI temporarily off. Nil if any write was accepted; otherwise the first
    /// write's error, which is logged. Stops before the next write once `valid` fails (a display or Space changed).
    /// `positionOnly` moves without resizing (re-anchoring a size-constrained window).
    func setFrame(_ goal: CGRect, on window: WindowRef, crossingDisplays: Bool, valid: () -> Bool = { true },
                  positionOnly: Bool = false) -> AXError? {
        guard valid() else { return .cannotComplete }
        if let writeOverride { return writeOverride(goal, window, crossingDisplays) ? nil : .cannotComplete }
        let element = window.element
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        AXUIElementSetMessagingTimeout(element, Self.timeout)

        let enhanced = AX.bool(app, Self.enhancedUI) == true
        if enhanced { AX.setBool(app, Self.enhancedUI, false) }
        defer { if enhanced { AX.setBool(app, Self.enhancedUI, true) } }

        let writes: [() -> AXError] = positionOnly ? [{ AX.setPosition(element, goal.origin) }]
            : crossingDisplays
            ? [{ AX.setSize(element, goal.size) }, { AX.setPosition(element, goal.origin) }, { AX.setSize(element, goal.size) }]
            : [{ AX.setPosition(element, goal.origin) }, { AX.setSize(element, goal.size) }]
        var results: [AXError] = []
        for write in writes {
            guard valid() else { break }
            results.append(write())
        }
        guard !results.contains(.success) else { return nil }
        let error = results.first ?? .cannotComplete
        Self.log.notice("set frame failed for \(window.bundleID ?? "?", privacy: .public): AXError \(error.rawValue, privacy: .public)")
        return error
    }

    /// Eases (cubic ease-out) from `start` toward `goal` in AX coordinates, without the final exact write.
    /// False when a newer move of the same window took over, or `valid` failed. The actor is free between frames.
    func glide(
        _ window: WindowRef, from start: CGRect, to goal: CGRect, duration: Double, key: UndoKey, generation: Int,
        valid: () -> Bool
    ) async -> Bool {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let enhanced = writeOverride == nil && AX.bool(app, Self.enhancedUI) == true
        if enhanced { AX.setBool(app, Self.enhancedUI, false) }
        defer { if enhanced { AX.setBool(app, Self.enhancedUI, true) } }

        let clock = ContinuousClock()
        let begin = clock.now
        let total = Duration.seconds(duration)
        while true {
            guard valid() else { return false }
            let t = min((clock.now - begin) / total, 1)
            if t >= 1 { return true }
            let e = 1 - pow(1 - t, 3)
            let frame = CGRect(
                x: start.minX + (goal.minX - start.minX) * e, y: start.minY + (goal.minY - start.minY) * e,
                width: start.width + (goal.width - start.width) * e, height: start.height + (goal.height - start.height) * e)
            if let writeOverride { _ = writeOverride(frame, window, false) } else {
                _ = AX.setPosition(window.element, frame.origin)
                guard valid() else { return false }
                _ = AX.setSize(window.element, frame.size)
            }
            let slept = (try? await Task.sleep(for: Self.frameInterval)) != nil  // cancelled: stop, don't spin
            guard generations[key] == generation, slept else { return false }
        }
    }
}
