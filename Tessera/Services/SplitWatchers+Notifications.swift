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
        // Displays and Spaces can change during sleep with no screen-parameters notification afterwards.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The display list can still be partial here: wait for it to settle rather than act on half of it.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.displays.refresh()
                    self.reconcileTopologyWhenReady()
                    // Already settled: a display that left during sleep is retired now. Otherwise convergence does it.
                    if self.convergenceTask == nil { self.contextsChanged(spaceNotification: false) }
                    else { self.armSoon(after: .seconds(1)) }
                }
            }
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
                MainActor.assumeIsolated {
                    self?.joinSoon(pid: pid, launched: launched, activated: !launched)
                    if launched { self?.observeSoon(pid) }
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.unhiddenApp(pid) }
        }
    }

    /// A launching app's window-created observer, asked for now and a few times more: waiting for the next re-arm
    /// (and 30 s after a refusal) misses the windows it opens meanwhile.
    func observeSoon(_ pid: pid_t) {
        Task { [weak self] in
            for delay in [0, 1, 2, 4] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, Permissions.isAccessibilityTrusted, self.model.settings.learnSplits,
                      NSRunningApplication(processIdentifier: pid)?.isTerminated == false else { return }
                self.lifecycle.observe(pid)
                if self.lifecycle.observes(pid) { return }
            }
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
