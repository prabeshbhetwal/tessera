import AppKit
import TesseraCore

extension SplitWatchers {
    func connectNotifications() {
        workspaceStore.onEvicted = { [weak self] record in
            for entry in record.restores { self?.minimisedWindows.forget(window: entry.window) }
        }
        if Permissions.isAccessibilityTrusted { lifecycle.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.contextsChanged(spaceNotification: true) }
        }
        minimisedWindows.onRestored = { [weak self] window, _, _ in self?.restoredWindow(window) }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.applicationTerminated(pid) }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                let launched = note.name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated { self?.joinSoon(pid: pid, launched: launched) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.unhiddenApp(pid) }
        }
    }

    func applicationTerminated(_ pid: pid_t) {
        snapshotActiveWorkspaces()
        let affected = workspaceStore.terminated(pid, retainReopen: model.settings.learnSplits && model.settings.splitFillsClosedGap)
        lifecycleLog.notice("App termination: pid \(pid), managed workspaces \(affected.count)")
        for watcher in watchers.values where watcher.watches(pid: pid) { watcher.closed() }
        // Suspended records retain their departure; active records without a child can recover immediately.
        for key in affected where currentWorkspaceKeys().contains(key)
            && pendingFills[key.display] == nil && watchers[key.display]?.watches(pid: pid) != true {
            resumeWorkspace(key)
        }
        minimisedWindows.forget(pid: pid)
    }
}
