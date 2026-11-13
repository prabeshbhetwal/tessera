import AppKit
import TesseraCore

extension SplitWatchers {
    func manualOverrides(_ window: WindowRef, goal: CGRect, ticket: WindowMutationContext.Ticket) -> Set<String> {
        var result: Set<String> = []
        for display in displays.displays where ticket.topology.contains(display) {
            let key = workspaceKey(display.id.storageKey, ticket: ticket)
            guard let record = workspaceStore[key], !record.members.isEmpty else { continue }
            let group = record.frames(in: ticket.topology)
            let member = group.contains { sameIdentity($0.window, window) }
            let destination = display.frame.contains(CGPoint(x: goal.midX, y: goal.midY))
            if member, !destination { result.insert(key.display); continue }
            guard destination else { continue }
            let candidate = group.filter { !sameIdentity($0.window, window) } + [(window: window, frame: goal)]
            let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
            if case .failure = SplitLearner.learn(candidate.map { ($0.window.bundleID, $0.frame) }, usable: usable, gap: display.profile.gap) {
                result.insert(key.display)
            }
        }
        return result
    }

    func relinquish(_ displays: Set<String>, windows: [WindowRef]) {
        for display in displays {
            pendingFills[display]?.cancel(); pendingFills[display] = nil
            fillIDs[display] = nil; fillGroups[display] = nil
            pendingResumes[display]?.cancel(); pendingResumes[display] = nil; resumeIDs[display] = nil
            watchers[display]?.stop()
            if let key = activeWorkspaceKeys[display] { workspaceStore.remove(key) }
        }
        // An all-Desktops window is the same physical window in each record; its manual override invalidates them too.
        let active = currentWorkspaceKeys()
        for (key, record) in workspaceStore.records where !active.contains(key) && record.members.contains(where: { entry in
            windows.contains { sameIdentity(entry.window, $0) }
        }) { workspaceStore.remove(key) }
        noLearn = noLearn.filter { !displays.contains($0.display) }
    }

    private func sameIdentity(_ a: WindowRef, _ b: WindowRef) -> Bool {
        a == b || (a.pid == b.pid && a.windowID != nil && a.windowID == b.windowID)
    }
}
