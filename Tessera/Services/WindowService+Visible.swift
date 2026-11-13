import AppKit
import ApplicationServices
import TesseraCore

/// Gathering the windows a Tile or split works on. Kept apart from `WindowService.swift` for its line limit.
extension WindowService {
    /// Standard windows of regular apps whose centre is on `display` (AppKit frame), with their AppKit frames, for
    /// tiling and splits. Skips Tessera, apps in `excluding`, minimised, hidden and full-screen windows, panels and
    /// dialogs, anything smaller than a tiny utility window, and windows wholly covered by others: a buried duplicate
    /// is not one the user sees. Kept anyway: windows in `retaining` (a split's own members), and new windows of
    /// `joiningPID` (not in `existingWindowIDs`) that its expanded survivor may cover. Front-most first.
    func visibleWindows(on display: CGRect, primaryHeight: CGFloat, excluding: Set<String>, retaining: [WindowRef] = [],
                        includingNewWindowsOf joiningPID: pid_t? = nil, existingWindowIDs: Set<CGWindowID> = [])
        -> [(window: WindowRef, frame: CGRect)] {
        visibleWindowsCounted(on: display, primaryHeight: primaryHeight, excluding: excluding, retaining: retaining,
                              includingNewWindowsOf: joiningPID, existingWindowIDs: existingWindowIDs).found
    }

    /// `visibleWindows`, plus how many apps with windows there were skipped because their Accessibility read failed
    /// (timed out or refused), so Tile can say so instead of ignoring them.
    func visibleWindowsCounted(on display: CGRect, primaryHeight: CGFloat, excluding: Set<String>,
                               retaining: [WindowRef] = [], includingNewWindowsOf joiningPID: pid_t? = nil,
                               existingWindowIDs: Set<CGWindowID> = [])
        -> (found: [(window: WindowRef, frame: CGRect)], skipped: Int) {
        if let visibleOverride { return (visibleOverride(display, primaryHeight, excluding, retaining), 0) }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return ([], 0) }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var windowsByPID: [pid_t: Set<CGWindowID>] = [:]
        var depth: [CGWindowID: Int] = [:]  // the list runs front to back
        for (z, info) in list.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            // CG gives which windows are on screen and their stacking. Their CG bounds are presentation geometry,
            // which Mission Control transforms, so size and position come from AX below.
            windowsByPID[pid, default: []].insert(id)
            depth[id] = z
        }

        var result: [(window: WindowRef, frame: CGRect)] = []
        var skipped = 0
        for (pid, ids) in windowsByPID {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, !app.isHidden,
                  !excluding.contains(app.bundleIdentifier ?? "") else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Self.timeout)
            guard let windows = AX.value(axApp, kAXWindowsAttribute) as? [AXUIElement] else {
                skipped += 1
                Self.log.notice("skipped \(app.bundleIdentifier ?? "?", privacy: .public): its windows couldn't be read")
                continue
            }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, Self.timeout)
                // A full-screen window has a Space of its own: tiling or a split must not pull it out.
                guard let id = SPI.windowID(of: element), ids.contains(id), AX.bool(element, kAXMinimizedAttribute) != true,
                      AX.bool(element, "AXFullScreen") != true,
                      (AX.value(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      let bounds = AX.frame(element), bounds.width >= 120, bounds.height >= 80 else { continue }
                let frame = CoordinateSpace.fromAX(bounds, primaryHeight: primaryHeight)
                guard display.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
                result.append((WindowRef(element: element, pid: pid, windowID: id, bundleID: app.bundleIdentifier), frame))
            }
        }
        let ordered = result.sorted { depth[$0.window.windowID ?? 0, default: .max] < depth[$1.window.windowID ?? 0, default: .max] }
        let exposed = Set(WindowVisibility.exposedIndices(ordered.map(\.frame)))
        let found = ordered.enumerated().filter { entry in
            exposed.contains(entry.offset) || retaining.contains(entry.element.window)
                || (entry.element.window.pid == joiningPID
                    && entry.element.window.windowID.map { !existingWindowIDs.contains($0) } == true)
        }.map(\.element)
        return (found, skipped)
    }
}
