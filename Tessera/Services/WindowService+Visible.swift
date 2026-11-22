import AppKit
import ApplicationServices
import TesseraCore

/// Gathering the windows a Tile or split works on. Kept apart from `WindowService.swift` for its line limit.
extension WindowService {
    /// Standard windows of regular apps whose centre is on `display` (AppKit frame), with their AppKit frames, for
    /// tiling and splits. Skips Tessera, apps in `excluding`, minimised, hidden and full-screen windows, panels and
    /// dialogs, fixed-size windows (their size isn't settable), anything smaller than a tiny utility window, and windows
    /// wholly covered by others (fixed-size windows still count as covers): a buried duplicate
    /// is not one the user sees. Kept anyway: windows in `retaining` (a split's own members), and new windows of
    /// `joiningPID` (not in `existingWindowIDs`) that its expanded survivor may cover. `keepingCoveredByNewcomer`
    /// judges the other windows as if the joining app's new windows were not there (a display with no group, where a
    /// newcomer opens over the only other window); what was already buried stays out. `patient` asks one silent app
    /// again with a longer timeout. `skipped` counts only apps with a window on this display. Front-most first.
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
                               existingWindowIDs: Set<CGWindowID> = [], keepingCoveredByNewcomer: Bool = false,
                               patient: Bool = false)
        -> (found: [(window: WindowRef, frame: CGRect)], skipped: Int, unread: [CGRect]) {
        if let visibleOverride { return (visibleOverride(display, primaryHeight, excluding, retaining), 0, []) }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return ([], 0, []) }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var windowsByPID: [pid_t: Set<CGWindowID>] = [:]
        var pidsHere: Set<pid_t> = []
        var framesHere: [pid_t: [CGRect]] = [:]
        var depth: [CGWindowID: Int] = [:]  // the list runs front to back
        for (z, info) in list.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            // CG gives which windows are on screen and their stacking. Their CG bounds are presentation geometry,
            // which Mission Control transforms, so size and position come from AX below.
            windowsByPID[pid, default: []].insert(id)
            orderedOut.remove(id)
            // CG bounds are good enough to say which display an unreadable app's windows are on.
            if let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) {
                let frame = CoordinateSpace.fromAX(bounds, primaryHeight: primaryHeight)
                if display.contains(CGPoint(x: frame.midX, y: frame.midY)) { pidsHere.insert(pid); framesHere[pid, default: []].append(frame) }
            }
            depth[id] = z
        }

        var result: [(window: WindowRef, frame: CGRect, resizable: Bool)] = []
        var skipped = 0
        var unread: [CGRect] = []
        var patient = patient
        for (pid, ids) in windowsByPID {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, !app.isHidden,
                  !excluding.contains(app.bundleIdentifier ?? "") else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Self.timeout)
            var answer = AX.value(axApp, kAXWindowsAttribute) as? [AXUIElement]
            // A busy Chromium or Electron app often misses the short timeout. One slower ask per read, on this actor
            // and off the main thread, before its windows are left out; a second silent app is not waited for.
            if answer == nil, patient, pidsHere.contains(pid) {
                patient = false
                AXUIElementSetMessagingTimeout(axApp, 1)
                answer = AX.value(axApp, kAXWindowsAttribute) as? [AXUIElement]
            }
            guard let windows = answer else {
                if pidsHere.contains(pid) { skipped += 1; unread += framesHere[pid] ?? [] }
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
                // A window Tessera can't resize (Finder's error alert, an About box) is never tiled, joined or watched,
                // or a stream of alerts would shrink its neighbours on open and grow them back on close.
                let resizable = AX.sizeSettable(element)
                if !resizable { Self.log.debug("skipped \(app.bundleIdentifier ?? "?", privacy: .public) window: size not settable") }
                result.append((WindowRef(element: element, pid: pid, windowID: id, bundleID: app.bundleIdentifier), frame, resizable))
            }
        }
        let ordered = result.sorted { depth[$0.window.windowID ?? 0, default: .max] < depth[$1.window.windowID ?? 0, default: .max] }
        let forced = ordered.map { entry in
            retaining.contains(entry.window)
                || (entry.window.pid == joiningPID && entry.window.windowID.map { !existingWindowIDs.contains($0) } == true)
        }
        let newcomer = ordered.map { entry in
            entry.window.pid == joiningPID && entry.window.windowID.map { !existingWindowIDs.contains($0) } == true
        }
        // The others as they were before the newcomer opened over them.
        // A fixed-size newcomer (a splash, an About box) is never tiled, so it still covers what is under it.
        let others = keepingCoveredByNewcomer ? ordered.indices.filter { !(newcomer[$0] && ordered[$0].resizable) }
            : Array(ordered.indices)
        let kept = Set(WindowVisibility.selectedIndices(others.map { ordered[$0].frame }, resizable: others.map { ordered[$0].resizable },
                                                        forced: others.map { forced[$0] }).map { others[$0] })
        let found = ordered.indices.filter { kept.contains($0) || (keepingCoveredByNewcomer && newcomer[$0] && ordered[$0].resizable) }
            .map { (window: ordered[$0].window, frame: ordered[$0].frame) }
        return (found, skipped, unread)
    }
}
