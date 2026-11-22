import AppKit
import CoreGraphics
import TesseraCore

extension WindowService {
    /// True for minimisation, false for destruction, nil while still live or intentionally hidden.
    func removalKind(of window: WindowRef) -> Bool? {
        if let removalOverride { return removalOverride(window) }
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
            if let id = window.windowID { orderedOut.remove(id) }
            return false
        }
        if let id = window.windowID, orderedOut.contains(id) { return false }
        guard !app.isHidden else { return nil }
        AXUIElementSetMessagingTimeout(window.element, 0.3)
        if AX.bool(window.element, kAXMinimizedAttribute) == true { return true }
        return AX.isValid(window.element) ? nil : false
    }

    /// True when the window is off screen now and its app no longer lists it although its element still answers:
    /// closed by ordering out (Slack, WhatsApp). The caller marks it (`markOrderedOut`) once its own checks stand.
    func isOrderedOut(_ window: WindowRef) -> Bool {
        guard let id = window.windowID else { return false }
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard !onScreen.isEmpty, !onScreen.contains(where: { $0[kCGWindowNumber as String] as? CGWindowID == id }) else { return false }
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        guard let listed = AX.value(app, kAXWindowsAttribute) as? [AXUIElement] else { return false }
        // A listed window whose ID can't be read may be this one: no answer, not "closed".
        let ids = listed.map { SPI.windowID(of: $0) }
        return !ids.contains(nil) && !ids.contains(id)
    }

    /// `removalKind` answers closed for these until they are seen on screen again or their app quits.
    func markOrderedOut(_ ids: [CGWindowID]) { orderedOut.formUnion(ids) }

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
