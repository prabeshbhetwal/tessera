import AppKit
import TesseraCore

extension HelpEvent {
    /// "Safari", falling back to the bundle identifier, then "Untitled".
    @MainActor
    static func appName(_ window: WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID ?? "Untitled"
    }

    /// Builds an event for `group` on `display`. `group` must already be in on-screen order (`onScreenOrder`); it is
    /// used as given so `apps`, `frames` and the key agree with the caller's own ordering.
    @MainActor
    static func make(kind: HelpEventKind, source: CommandSource, display: DisplayContext,
                     group: [(window: WindowRef, frame: CGRect)], split: LearnedSplit?,
                     previous: LearnedSplit?, undoMarker: Int? = nil) -> HelpEvent {
        let portrait = display.range.isPortrait
        let sorted = group
        return HelpEvent(
            kind: kind, source: source, displayKey: display.id.storageKey,
            displayName: NSScreen.screens.first { $0.frame == display.frame }?.localizedName ?? "this display",
            apps: sorted.map { appName($0.window) }, frames: sorted.map(\.frame),
            usable: GridGeometry.usableFrame(display.visibleFrame, profile: display.profile),
            portrait: portrait, key: SplitKey(sorted, on: display), split: split, previousSplit: previous,
            undoMarker: undoMarker)
    }
}

/// Windows in on-screen order: left to right, or top to bottom on a portrait display. Ties break deterministically
/// (portrait: leftmost first; landscape: topmost first), because `visibleWindows` order is not on-screen order.
func onScreenOrder(_ group: [(window: WindowRef, frame: CGRect)], portrait: Bool)
    -> [(window: WindowRef, frame: CGRect)] {
    group.sorted {
        if portrait {
            return $0.frame.midY != $1.frame.midY ? $0.frame.midY > $1.frame.midY : $0.frame.minX < $1.frame.minX
        }
        return $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.maxY > $1.frame.maxY
    }
}
