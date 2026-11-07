import AppKit
import TesseraCore

extension HelpEvent {
    /// "Safari": the running app's name, else (an app that just quit) the installed app's, then the bundle identifier,
    /// then "Untitled".
    @MainActor
    static func appName(_ window: WindowRef) -> String {
        if let name = NSRunningApplication(processIdentifier: window.pid)?.localizedName { return name }
        guard let id = window.bundleID else { return "Untitled" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Builds an event for `group` on `display`. `group` must already be in on-screen order (`onScreenOrder`); it is
    /// used as given so `apps`, `frames` and the key agree with the caller's own ordering.
    @MainActor
    static func make(kind: HelpEventKind, source: CommandSource, display: DisplayContext,
                     group: [(window: WindowRef, frame: CGRect)], split: LearnedSplit?,
                     previous: LearnedSplit?, undoMarker: Int? = nil) -> HelpEvent {
        let event = HelpEvent(
            kind: kind, source: source, displayKey: display.id.storageKey,
            displayName: NSScreen.screens.first { $0.frame == display.frame }?.localizedName ?? "this display",
            apps: group.map { appName($0.window) }, frames: group.map(\.frame),
            usable: GridGeometry.usableFrame(display.visibleFrame, profile: display.profile),
            portrait: display.range.isPortrait, key: SplitKey(group, on: display), split: split, previousSplit: previous,
            undoMarker: undoMarker)
        assert(event.apps.count == event.frames.count, "apps and frames must pair up")
        return event
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
