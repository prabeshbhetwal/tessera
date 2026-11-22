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
    func forget(_ windows: [WindowRef]) {
        for window in windows { if let id = window.windowID { knownWindows[window.pid]?.remove(id) } }
    }
    func focused(_ pid: pid_t) { onFocusChanged?(pid) }

    func created(_ pid: pid_t, windowID: CGWindowID?) {
        if let windowID, !knownWindows[pid, default: []].insert(windowID).inserted { return }
        onCreated?(pid, windowID)
    }

    private var observers: [pid_t: (AXObserver, AXUIElement)] = [:]
    /// Observers that got focus changes but not window-created: asked again for it.
    private var lacksCreated: Set<pid_t> = []
    func observes(_ pid: pid_t) -> Bool { observers[pid] != nil && !lacksCreated.contains(pid) }
    /// Apps whose registration failed (hung, or no AX support), with when: each attempt is a synchronous call into the
    /// app on the main thread, so a refusing app is retried only after `retryAfter`, not on every refresh.
    private var refusedAt: [pid_t: ContinuousClock.Instant] = [:]
    private static let retryAfter: Duration = .seconds(30)
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "window-lifecycle")

    /// Asks one app again now: a just-launched app often refuses until its run loop is up.
    func observe(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return }
        refusedAt[pid] = nil
        // The windows it already has are not new ones.
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let ids = rows.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t == pid ? $0[kCGWindowNumber as String] as? CGWindowID : nil }
        register(pid, current: [pid: Set(ids)])
    }

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
            lacksCreated.remove(pid)
        }
        refusedAt = refusedAt.filter { live.contains($0.key) && ContinuousClock.now - $0.value < Self.retryAfter }
        for app in apps where refusedAt[app.processIdentifier] == nil { register(app.processIdentifier, current: current) }
    }

    /// Creates the app's observer, or asks an observer that only got focus changes for window-created again.
    private func register(_ pid: pid_t, current: [pid_t: Set<CGWindowID>]?) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let entry = observers[pid] {
            guard lacksCreated.contains(pid) else { return }
            if AXObserverAddNotification(entry.0, entry.1, kAXWindowCreatedNotification as CFString, context) == .success {
                lacksCreated.remove(pid)
            } else {
                refusedAt[pid] = .now
            }
            return
        }
        // AX can announce an existing window again after unhide or accessibility-tree recreation.
        if let current { knownWindows[pid, default: []].formUnion(current[pid] ?? []) }
        var value: AXObserver?
        guard AXObserverCreate(pid, windowLifecycleCallback, &value) == .success, let observer = value else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        let created = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
        // A hung app that refused the first is not asked a second time on the main thread.
        let focus = created == .cannotComplete ? created
            : AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, context)
        guard created == .success || focus == .success else {
            refusedAt[pid] = .now
            log.notice("Window observation unavailable for pid \(pid): \(created.rawValue)")
            return
        }
        if created != .success { lacksCreated.insert(pid); refusedAt[pid] = .now }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = (observer, element)
    }
}

private func windowLifecycleCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                     _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    let observedPID = pid
    let created = notification as String == kAXWindowCreatedNotification
    // The read below is a call into the app that just created the window; never wait on it longer than other AX reads.
    AXUIElementSetMessagingTimeout(element, 0.3)
    let observedWindowID = created ? SPI.windowID(of: element) : nil
    let monitor = Unmanaged<WindowLifecycleMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        if created { monitor.created(observedPID, windowID: observedWindowID) }
        else { monitor.focused(observedPID) }
    }
}
