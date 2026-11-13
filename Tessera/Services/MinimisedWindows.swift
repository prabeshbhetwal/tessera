import AppKit
import ApplicationServices

/// Windows minimised out of a side-by-side group while `minimiseFillsGap` is on, so the rest covered their space. Each
/// is watched until it is restored, closed or its app quits; on restore, `onRestored` gets it with the windows it left
/// and their display, so it can be tiled back in.
///
/// Observers hold `self` unretained. That is safe because `SplitWatchers` keeps this for the app's lifetime and
/// `forget` removes a window's registration before dropping it.
@MainActor
final class MinimisedWindows {
    var onRestored: ((_ window: WindowRef, _ others: [WindowRef], _ displayKey: String) -> Void)?

    private static let notifications = [kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification]
    private var entries: [(window: WindowRef, others: [WindowRef], displayKey: String, observer: AXObserver)] = []

    /// Watches `window`, just minimised out of `others` on the display with this storage key.
    func add(_ window: WindowRef, others: [WindowRef], displayKey: String) {
        forget { $0 == window }
        var created: AXObserver?
        guard AXObserverCreate(window.pid, minimisedWindowCallback, &created) == .success, let observer = created
        else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXUIElementSetMessagingTimeout(window.element, 0.3)  // as `SplitWatcher`: a hung app never stalls the main thread
        let added = Self.notifications.filter {
            AXObserverAddNotification(observer, window.element, $0 as CFString, refcon) == .success
        }
        guard !added.isEmpty else { return }  // gone already: nothing would ever restore it
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        entries.append((window, others, displayKey, observer))
    }

    /// Stops watching the windows of an app that quit.
    func forget(pid: pid_t) { forget { $0.pid == pid } }
    func forget(window: WindowRef) { forget { $0 == window } }
    func forgetAll() { forget { _ in true } }

    private func forget(where matches: (WindowRef) -> Bool) {
        for entry in entries where matches(entry.window) {
            for name in Self.notifications {
                AXObserverRemoveNotification(entry.observer, entry.window.element, name as CFString)
            }
            let source = AXObserverGetRunLoopSource(entry.observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
        }
        entries.removeAll { matches($0.window) }
    }

    /// Restored or closed: either way the window is no longer waiting.
    fileprivate func handle(_ notification: String, element: AXUIElement) {
        guard let entry = entries.first(where: { CFEqual($0.window.element, element) }) else { return }
        forget { $0 == entry.window }
        guard notification == kAXWindowDeminiaturizedNotification else { return }
        onRestored?(entry.window, entry.others, entry.displayKey)
    }
}

/// AX calls this on the main run loop, where `add` puts every observer's source; `refcon` is the `MinimisedWindows`.
private func minimisedWindowCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                     _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let windows = Unmanaged<MinimisedWindows>.fromOpaque(refcon)
    let name = notification as String
    nonisolated(unsafe) let element = element  // never leaves the main thread this callback runs on
    MainActor.assumeIsolated {
        windows.takeUnretainedValue().handle(name, element: element)
    }
}
