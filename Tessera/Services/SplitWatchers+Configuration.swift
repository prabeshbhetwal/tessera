import AppKit
import TesseraCore

extension SplitWatchers {
    func layoutSettingsMatch(_ settings: TesseraSettings, on display: String) -> Bool {
        WindowLayoutPolicy.matches(settings, model.settings, display: display)
    }

    func configurationChanged(_ settings: TesseraSettings) {
        let affected = Set(displays.displays.map { $0.id.storageKey }.filter {
            !WindowLayoutPolicy.matches(lastLayoutSettings, settings, display: $0)
        })
        lastLayoutSettings = settings
        guard !affected.isEmpty else { return }
        snapshotActiveWorkspaces()
        windows.mutationContext.invalidateLayouts(on: affected)
        cancelLayouts(affected)
        displays.refresh()
        if !settings.learnSplits { stop(); return }
        if !settings.splitFillsClosedGap {
            for key in currentWorkspaceKeys() where affected.contains(key.display) {
                workspaceStore[key]?.recoveryPending = false
                workspaceStore[key]?.recovery = nil
            }
        }
        for key in affected {
            watchers[key]?.renewContext(windows.mutationContext.capture())
            let origin = workspaceKey(key)
            if workspaceStore[origin]?.recoveryPending == true, settings.splitFillsClosedGap { resumeWorkspace(origin) }
        }
        armSoon()
    }

    func cancelLayouts(_ displays: Set<String>) {
        for key in displays {
            pendingFills[key]?.cancel(); pendingFills[key] = nil; fillIDs[key] = nil; fillGroups[key] = nil
            pendingResumes[key]?.cancel(); pendingResumes[key] = nil; resumeIDs[key] = nil
            watchers[key]?.cancelAdjustment()
        }
    }

    /// ⌃⌥Z supersedes automatic recovery still under way: once Undo puts the windows back, the vacancy that recovery
    /// was filling must not be filled again by the next re-arm.
    func undoSupersedesRecovery() {
        let interrupted = Set(pendingFills.keys).union(pendingResumes.keys)
        guard !interrupted.isEmpty else { return }
        explicitLayout(on: interrupted, ticket: windows.mutationContext.capture())
    }

    func explicitLayout(on displays: Set<String>, ticket: WindowMutationContext.Ticket) {
        cancelLayouts(displays)
        for key in displays {
            let origin = workspaceKey(key, ticket: ticket)
            workspaceStore[origin]?.recoveryPending = false
            workspaceStore[origin]?.recovery = nil
            workspaceStore[origin]?.retryAfter = nil
            watchers[key]?.renewContext(ticket)
        }
    }

    func handAdjusted(_ display: String) {
        let original = windows.mutationContext.capture()
        guard activeWorkspaceKeys[display] == workspaceKey(display, ticket: original),
              let ticket = windows.mutationContext.overridingLayouts(original, on: [display]) else { return }
        pendingFills[display]?.cancel(); pendingFills[display] = nil; fillIDs[display] = nil; fillGroups[display] = nil
        pendingResumes[display]?.cancel(); pendingResumes[display] = nil; resumeIDs[display] = nil
        let key = workspaceKey(display, ticket: ticket)
        workspaceStore[key]?.recoveryPending = false
        workspaceStore[key]?.recovery = nil
        workspaceStore[key]?.retryAfter = nil
        watchers[display]?.acceptHandContext(ticket)
    }
}
