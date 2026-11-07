import AppKit
import TesseraCore

extension HelpEvent {
    /// "Safari", falling back to the bundle identifier, then "Untitled".
    @MainActor
    static func appName(_ window: WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID ?? "Untitled"
    }

    /// Builds an event for `group` on `display`. `group` is sorted into on-screen order first (left to right, or top
    /// to bottom on a portrait display): the watcher's `visibleWindows` order is not on-screen order.
    @MainActor
    static func make(kind: HelpEventKind, source: CommandSource, display: DisplayContext,
                     group: [(window: WindowRef, frame: CGRect)], split: LearnedSplit?,
                     previous: LearnedSplit?) -> HelpEvent {
        let portrait = display.range.isPortrait
        let sorted = group.sorted { portrait ? $0.frame.maxY > $1.frame.maxY : $0.frame.minX < $1.frame.minX }
        return HelpEvent(
            kind: kind, source: source, displayKey: display.id.storageKey,
            displayName: NSScreen.screens.first { $0.frame == display.frame }?.localizedName ?? "this display",
            apps: sorted.map { appName($0.window) }, frames: sorted.map(\.frame),
            usable: GridGeometry.usableFrame(display.visibleFrame, profile: display.profile),
            portrait: portrait, key: SplitKey(sorted, on: display), split: split, previousSplit: previous)
    }
}
