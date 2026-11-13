import AppKit
import CoreGraphics
import TesseraCore

extension WindowService {
    /// True for minimisation, false for destruction, nil while still live or intentionally hidden.
    func removalKind(of window: WindowRef) -> Bool? {
        if let removalOverride { return removalOverride(window) }
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { return false }
        guard !app.isHidden else { return nil }
        AXUIElementSetMessagingTimeout(window.element, 0.3)
        if AX.bool(window.element, kAXMinimizedAttribute) == true { return true }
        return AX.isValid(window.element) ? nil : false
    }

    /// A close can arrive before a watch's delayed baseline refresh. Keep verified writes available for that gap.
    func rememberPlacement(_ frame: CGRect, of window: WindowRef) {
        // The move's own ticket: a fresh capture is a WindowServer round trip per window, and maps onto a newer layout.
        let topology = (WindowMutationScope.ticket ?? mutationContext.capture()).topology
        placements[Self.key(for: window)] = (topology.placement(frame), .now)
        if placements.count > 500, let oldest = placements.min(by: { $0.value.at < $1.value.at })?.key {
            placements[oldest] = nil
        }
    }

    func placement(of window: WindowRef, after baseline: ContinuousClock.Instant, primaryHeight: CGFloat) -> CGRect? {
        guard let entry = placements[Self.key(for: window)], entry.at > baseline else { return nil }
        let frame = entry.placement.resolved(in: (WindowMutationScope.ticket ?? mutationContext.capture()).topology.recoveryDisplays)
        return CoordinateSpace.fromAX(frame, primaryHeight: primaryHeight)
    }
}
