import AppKit
import ApplicationServices
import os

/// Observes app-level window creation, including Cmd-N and windows created without activating their app.
@MainActor
final class WindowLifecycleMonitor {
    var onCreated: ((pid_t, CGWindowID?) -> Void)?
    var onFocusChanged: ((pid_t) -> Void)?
    private var knownWindows: [pid_t: Set<CGWindowID>]
    init(existingWindows: [pid_t: Set<CGWindowID>] = [:]) { knownWindows = existingWindows }
    func windowIDs(_ pid: pid_t) -> Set<CGWindowID> { knownWindows[pid] ?? [] }
    func remember(_ windows: [WindowRef]) {
        for window in windows { if let id = window.windowID { knownWindows[window.pid, default: []].insert(id) } }
    }
    func focused(_ pid: pid_t) { onFocusChanged?(pid) }

    func created(_ pid: pid_t, windowID: CGWindowID?) {
        if let windowID, !knownWindows[pid, default: []].insert(windowID).inserted { return }
        onCreated?(pid, windowID)
    }

    private var observers: [pid_t: (AXObserver, AXUIElement)] = [:]
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "window-lifecycle")

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let live = Set(apps.map(\.processIdentifier))
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        var current: [pid_t: Set<CGWindowID>] = [:]
        for row in rows {
            if let pid = row[kCGWindowOwnerPID as String] as? pid_t, let id = row[kCGWindowNumber as String] as? CGWindowID {
                current[pid, default: []].insert(id)
            }
        }
        for pid in Array(knownWindows.keys) { knownWindows[pid]?.formIntersection(current[pid] ?? []) }
        for pid in Array(observers.keys) where !live.contains(pid) {
            if let entry = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.0), .commonModes)
            }
            knownWindows[pid] = nil
        }
        for app in apps where observers[app.processIdentifier] == nil {
            let pid = app.processIdentifier
            // AX can announce an existing window again after unhide or accessibility-tree recreation.
            knownWindows[pid, default: []].formUnion(current[pid] ?? [])
            var value: AXObserver?
            guard AXObserverCreate(pid, windowLifecycleCallback, &value) == .success, let observer = value else { continue }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.3)
            let result = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString,
                                                   Unmanaged.passUnretained(self).toOpaque())
            let focus = AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString,
                                                  Unmanaged.passUnretained(self).toOpaque())
            guard result == .success || focus == .success else {
                log.debug("Window-created observation unavailable for pid \(pid): \(result.rawValue)")
                continue
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = (observer, element)
        }
    }


}

private func windowLifecycleCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                     _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    let observedPID = pid
    let created = notification as String == kAXWindowCreatedNotification
    let observedWindowID = created ? SPI.windowID(of: element) : nil
    let monitor = Unmanaged<WindowLifecycleMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        if created { monitor.created(observedPID, windowID: observedWindowID) }
        else { monitor.focused(observedPID) }
    }
}
