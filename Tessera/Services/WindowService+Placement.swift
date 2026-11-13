import AppKit
import TesseraCore

extension WindowService {
    /// Writes an AX frame with Enhanced UI temporarily off. True if any write was accepted.
    func setFrame(_ goal: CGRect, on window: WindowRef, crossingDisplays: Bool, valid: () -> Bool = { true }) -> Bool {
        guard valid() else { return false }
        if let writeOverride {
            let accepted = writeOverride(goal, window, crossingDisplays)
            if accepted, let actual = readFrame(window) { rememberPlacement(actual, of: window) }
            return accepted
        }
        let element = window.element
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        AXUIElementSetMessagingTimeout(element, Self.timeout)

        let enhanced = writeOverride == nil && AX.bool(app, Self.enhancedUI) == true
        if enhanced { AX.setBool(app, Self.enhancedUI, false) }
        defer { if enhanced { AX.setBool(app, Self.enhancedUI, true) } }

        var accepted = false
        if crossingDisplays {
            guard valid() else { return accepted }
            accepted = AX.setSize(element, goal.size) || accepted
        }
        guard valid() else { return accepted }
        accepted = AX.setPosition(element, goal.origin) || accepted
        guard valid() else { return accepted }
        accepted = AX.setSize(element, goal.size) || accepted
        if accepted, let actual = readFrame(window) { rememberPlacement(actual, of: window) }
        return accepted
    }

    /// Eases (cubic ease-out) from `start` toward `goal` in AX coordinates, without the final exact write.
    /// False when a newer move of the same window took over. The actor is free between frames.
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
            guard !Task.isCancelled, valid() else { return false }
            let t = min((clock.now - begin) / total, 1)
            if t >= 1 { return true }
            let e = 1 - pow(1 - t, 3)
            let frame = CGRect(
                x: start.minX + (goal.minX - start.minX) * e, y: start.minY + (goal.minY - start.minY) * e,
                width: start.width + (goal.width - start.width) * e, height: start.height + (goal.height - start.height) * e)
            if let writeOverride { _ = writeOverride(frame, window, false) }
            else {
                _ = AX.setPosition(window.element, frame.origin)
                guard valid() else { return false }
                _ = AX.setSize(window.element, frame.size)
            }
            let slept = (try? await Task.sleep(for: Self.frameInterval)) != nil  // cancelled: stop, don't spin
            guard generations[key] == generation, slept, valid() else { return false }
        }
    }

}
