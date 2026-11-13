import AppKit
import ApplicationServices
import os

/// What one ⌃⌥Z did (`WindowService.undoLast`).
enum UndoOutcome: Sendable {
    case restored
    case nothing
    /// Every live window of the latest step refused its old frame; the step is kept for another try.
    case refused(WindowRef)
}

extension ApplyResult {
    /// Where the window ended up, when this move wrote it: nil when it failed or a newer move took over.
    var landed: CGRect? {
        switch self {
        case let .applied(frame), let .constrained(frame): frame
        case .superseded, .failed: nil
        }
    }

    var failed: Bool { if case .failed = self { true } else { false } }
    var constrained: Bool { if case .constrained = self { true } else { false } }
}

/// Why a move failed, in words short enough for the HUD. Kept apart from `WindowService.swift` for its line limit.
extension WindowService {
    static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "windows")

    /// How far under its target a window may land before it counts as constrained. Apps that resize in
    /// character-cell steps (Terminal, iTerm) land a few points short on nearly every move; that is not worth a note.
    static let constrainedShortfall: CGFloat = 32

    /// True when the window landed larger than asked (a minimum size) or well short of it. The 1 pt re-anchoring
    /// check in `apply` is separate: any size difference moves the window back onto the targeted edges.
    static func isConstrained(landed: CGSize, goal: CGSize) -> Bool {
        landed.width > goal.width + 1 || landed.height > goal.height + 1
            || landed.width < goal.width - constrainedShortfall || landed.height < goal.height - constrainedShortfall
    }

    static let refusedMessage = "The app didn’t accept the new frame"
    static let unreadableMessage = "Can’t read the window’s frame"
    static let fullScreenMessage = "Full-screen windows can’t be moved"

    /// False for the generic messages, which the ring words as "Can't move this window".
    static func isSpecific(_ reason: String) -> Bool {
        reason != refusedMessage && reason != unreadableMessage
    }

    /// A short reason for a refused frame write.
    static func reason(for error: AXError) -> String {
        switch error {
        case .apiDisabled: "Accessibility was turned off"
        case .cannotComplete: "The app is not responding"
        case .attributeUnsupported, .notImplemented, .illegalArgument: "This window can’t be moved or resized"
        default: refusedMessage
        }
    }

    /// Why `window` can't be moved as it is (full screen, minimised, a sheet), or nil. Costs up to three AX reads,
    /// so only failure paths call it.
    static func unmovableReason(of window: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(window, timeout)
        if AX.bool(window, "AXFullScreen") == true { return fullScreenMessage }
        if AX.bool(window, kAXMinimizedAttribute) == true { return "Restore the window from the Dock first" }
        if (AX.value(window, kAXRoleAttribute) as? String) == kAXSheetRole { return "Close the sheet first" }
        return nil
    }

    /// After `frontmostWindow` or `frame(of:)` came back empty: a specific reason, or nil for the genuine
    /// "No window to move" (no window at all, or Tessera in front).
    func whyNoWindow(_ window: WindowRef?) -> String? {
        if let window { return Self.unmovableReason(of: window.element) }
        guard let pid = Self.frontmostPID(), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        guard let first = (AX.value(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { return nil }
        return Self.unmovableReason(of: first)
    }

    /// True when an undo write failed because the window or its app no longer exists, so the step can be dropped.
    static func isGone(_ window: WindowRef, error: AXError) -> Bool {
        error == .invalidUIElement || NSRunningApplication(processIdentifier: window.pid)?.isTerminated ?? true
    }
}
