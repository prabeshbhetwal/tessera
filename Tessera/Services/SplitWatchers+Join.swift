import AppKit
import TesseraCore

/// A window opening on a display gets a place there (`splitTilesNewWindow`): beside a side-by-side group it joins the
/// group, in the learned split for the apps now there when there is one, otherwise in equal shares. A hand adjustment
/// afterwards is learned as usual, so the next time those apps meet they get it. One ⌃⌥Z puts them back.
/// Equal shares wait `splitNewWindowWait` seconds and apply only if the window is still open then. A window that can't
/// zoom (a progress window such as Finder's Copy) never joins.
///
/// Only the launched or activated app's windows count as joining, so a Space switch or an unhidden app never re-tiles
/// a display. `splitNewWindowScope` picks the displays: only ones whose windows already sat side by side (a watched
/// group); also, for an app just launched or a window just created, any display where the apps now there have a
/// learned split; or any display holding two or more apps (`JoinDecision`). A window restored after the rest covered
/// its space (`minimiseFillsGap`) joins the windows it left the same way.
extension SplitWatchers {
    /// What one look needs: the groups as they stood at the event, and what the event allows.
    struct JoinRequest {
        let pid: pid_t
        let trigger: String
        /// The Space and display layout the event belongs to: a look never tiles on another one.
        let origin: WindowMutationContext.Ticket
        /// Group members at the event: never counted as new, however the groups change during the look.
        let known: [String: [WindowRef]]
        var groups: [String: [WindowRef]]
        let startsGroups: Bool
        let restored: Bool
        let existing: Set<CGWindowID>
        let restoringMinimised: Bool
        /// The app was launched, or reopened from the Dock with no window on screen until now: only such an app
        /// starts a group in equal shares (`JoinDecision`).
        let freshApp: Bool
        var holds = false
        /// First sightings: an equal-shares start waits a second to see the window is still there.
        var settles = false
        var waiting: (now: [WindowRef], allowed: [WindowRef])?
        /// The last retry decides on what it can read rather than give up on an app that never answers.
        var lastAttempt = false
        /// A look after a hold stays on the displays the newcomers were held on.
        var displaysOnly: Set<String>?
    }

    /// The groups are read now, before anything awaits: the activation also re-arms the watchers (`Coordinator`), which
    /// stops a watch once a window overlaps it. Each retry adds the groups formed since. A launch looks a few times,
    /// since its first window can take a while. `restoring` is set for a window restored after the rest covered its
    /// space (`MinimisedWindows`): it joins the windows it left, even when only one of them is left there.
    func joinSoon(pid: pid_t, launched: Bool, activated: Bool = false, windowCreated: Bool = false,
                  createdWindowID: CGWindowID? = nil, restoring: (others: [WindowRef], displayKey: String)? = nil) {
        let settings = model.settings
        guard settings.learnSplits, settings.splitTilesNewWindow || restoring != nil, pid != ProcessInfo.processInfo.processIdentifier
        else { return }
        // An app relaunched after quitting out of a group (the rest covered its space) comes back to the windows it left.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        // Peers whose app has quit since are no group to come back to.
        let contexts = (bundleID.flatMap { closedOutOf[$0] } ?? [:])
            .mapValues { $0.filter { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated == false } }
            .filter { !$0.value.isEmpty }
        let restored = restoring != nil || !contexts.isEmpty
        // A just-launched or restored app activates too: keep that look (its retries, groups and scope).
        if !launched, restoring == nil, !windowCreated, firstWindowLooks.contains(pid) { return }
        // Brought to the front with no window on screen (a Dock click on an app whose windows were closed or hidden):
        // the window it shows next is a new one, even if the app reuses the closed window's ID. Treated as a launch.
        // Not an unhide (its windows are old ones coming back), and none of its windows is minimised: a window restored
        // from the Dock is not a new one.
        // Only a real activation (a Dock click), not a focus change after an app closed its last window, and never Finder,
        // which comes to the front with no window whenever the desktop is clicked.
        let reopened = activated && !launched && !windowCreated && restoring == nil
            && NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.finder"
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && Self.onScreenWindows(of: pid).isEmpty
            && NSRunningApplication(processIdentifier: pid)?.isHidden == false && !wasUnhidden(pid) && !Self.hasMinimisedWindow(pid)
        // A window announced during a launch look restarts it as a launch look: the app's first window stays new.
        let asLaunch = launched || reopened || (windowCreated && restoring == nil && launchLooks.contains(pid))
        let now = windows.mutationContext.capture()
        // A restarted launch look still belongs to the Space and layout the launch began on. Any other event is a new
        // one with its own origin; a look whose origin a Tile or snap has since overtaken gives up its new windows.
        let restartsLaunch = asLaunch && !launched && !reopened && pendingJoins[pid] != nil
        if !restartsLaunch, let old = lookOrigins[pid], old.layoutEpochs != now.layoutEpochs, let ids = pendingNewWindows[pid] {
            let moved = Set(now.topology.keys.filter { old.layoutEpochs[$0, default: 0] != now.layoutEpochs[$0, default: 0] })
            let located = Self.displayKeys(of: ids, in: now.topology)
            pendingNewWindows[pid] = ids.filter { id in located[id].map { !moved.contains($0) } ?? true }
        }
        let origin = (restartsLaunch ? lookOrigins[pid] : nil) ?? now
        var tiled = watchers.filter { !$0.value.watched.isEmpty }.mapValues(\.watched)
        for (display, others) in contexts where tiled[display] == nil { tiled[display] = others }
        if let restoring, tiled[restoring.displayKey] == nil { tiled[restoring.displayKey] = restoring.others }
        let startsGroups = launched || reopened || windowCreated
        // An activation only ever joins a group that is there now; a launch may meet one formed while it loads, and on
        // the narrow scope that is the only way it can tile.
        guard !tiled.isEmpty || (startsGroups && settings.splitNewWindowScope != .tiledDisplays) else {
            decisionLog.debug("join skipped: no group; pid \(pid)")
            return
        }
        if let createdWindowID { pendingNewWindows[pid, default: []].insert(createdWindowID) }
        let existing = asLaunch ? [] : lifecycle.windowIDs(pid).subtracting(pendingNewWindows[pid] ?? [])
        pendingJoins[pid]?.cancel()
        if launched || reopened || restored || windowCreated { firstWindowLooks.insert(pid) } else { firstWindowLooks.remove(pid) }
        if asLaunch { launchLooks.insert(pid) } else { launchLooks.remove(pid) }
        lookOrigins[pid] = origin
        // One more window of a running app (⌘N, a pop-up from the background) starts no group; a Dock reopen does.
        let freshApp = asLaunch || (windowCreated && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            && Self.onScreenWindows(of: pid).subtracting(pendingNewWindows[pid] ?? []).isEmpty)
        let trigger = restoring != nil ? "restore" : launched ? "launch" : reopened ? "reopen" : windowCreated ? "created" : "activate"
        let request = JoinRequest(pid: pid, trigger: trigger, origin: origin, known: tiled, groups: tiled,
                                  startsGroups: startsGroups, restored: restored, existing: existing,
                                  restoringMinimised: restoring != nil, freshApp: freshApp)
        let delays = startsGroups ? [500, 1000, 1500, 2000, 2000, 2000, 3000] : [500, 1000, 1500]
        let wait = restored ? 0 : settings.splitNewWindowWaitSeconds
        pendingJoins[pid] = Task { [weak self] in
            // A replaced look leaves the bookkeeping to the look that replaced it.
            defer {
                if !Task.isCancelled {
                    self?.pendingJoins[pid] = nil
                    self?.firstWindowLooks.remove(pid)
                    self?.launchLooks.remove(pid)
                    self?.lookOrigins[pid] = nil
                    self?.pendingNewWindows[pid] = nil
                }
            }
            // An activated app's window can show late too (an Electron window shown from the Dock), so every look
            // retries. A cold launch can take several seconds to show its first window (WhatsApp, Wispr Flow, Dia), so
            // a launch looks for 12 s.
            var reason = "noWindowYet"
            // Holds add their own wait; the look still ends close to its schedule.
            let deadline = ContinuousClock.now + .milliseconds(delays.reduce(0, +) + 3000)
            for (index, delay) in delays.enumerated() {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                guard let self else { return }
                if !launched, restoring == nil, !windowCreated, self.wasUnhidden(pid) { return }
                var attempt = request
                attempt.holds = wait > 0
                attempt.settles = true
                attempt.lastAttempt = index == delays.count - 1
                let (look, why) = await self.look(attempt)
                switch look {
                case .tiled:
                    self.logJoin(request, bundleID: bundleID, outcome: "tiled", reason: why)
                    return
                case .stopped:
                    self.logJoin(request, bundleID: bundleID, outcome: "stopped", reason: why)
                    return
                case .notFound: reason = why
                case .held(let first):
                    // A first-sighting settle is one second; the "Wait before tiling" setting is for equal shares.
                    let outcome = await self.hold(first, request: request, wait: why == "settle" ? 1 : max(wait, 1), until: deadline)
                    if Task.isCancelled { return }
                    // The window that waited is gone (a sign-in or loading window): the app's real one may still come.
                    if !outcome.tiled, !outcome.stop, index < delays.count - 1, ContinuousClock.now < deadline {
                        reason = outcome.reason; continue
                    }
                    self.logJoin(request, bundleID: bundleID, outcome: outcome.tiled ? "tiled" : "notTiled", reason: outcome.reason)
                    return
                }
            }
            if !Task.isCancelled { self?.logJoin(request, bundleID: bundleID, outcome: "notTiled", reason: reason) }
        }
    }

    /// `stopped`: the setting went off, Accessibility went away, or the user's own layout or Space took over.
    enum JoinLook: Equatable { case tiled, held([WindowRef]), notFound, stopped }

    /// One attempt, on a fresh ticket and with the groups formed since the event. The ticket must still describe the
    /// event's display layout; each display is checked against the event's Space in `join`.
    private func look(_ request: JoinRequest) async -> (JoinLook, String) {
        let ticket = windows.mutationContext.capture()
        guard ticket.topologyVersion == request.origin.topologyVersion else { return (.notFound, "displaysChanged") }
        var attempt = request
        for (display, watcher) in watchers where !watcher.watched.isEmpty { attempt.groups[display] = watcher.watched }
        return await WindowMutationScope.$ticket.withValue(ticket) { await join(attempt) }
    }

    /// No learned split for these apps: only a window still open after the wait is tiled in, so one opened for a moment
    /// (Wispr Flow, Finder) is left alone. A window the app opens during the wait waits its own turn.
    private func hold(_ first: [WindowRef], request: JoinRequest, wait: Int, until deadline: ContinuousClock.Instant) async
        -> (tiled: Bool, stop: Bool, reason: String) {
        var waiting = (now: first, allowed: first)
        var tiledAny = false
        var pinned: Set<String>?
        waiting: while true {
            // Baseline only once Tessera's own glides have settled, or a frame read mid-glide looks like a hand change.
            for _ in 0..<30 where ownMoves > 0 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return (tiledAny, true, "cancelled") }
            }
            let movesBefore = ownMoveCount
            // Only the groups on the displays the newcomers wait on: a hand change to a split on another display must
            // not cancel this join. The newcomers themselves only have to stay open; an app may still size its window.
            var waitingOn = Set<String>()
            for ref in waiting.allowed {
                guard let frame = await windows.frame(of: ref) else { continue }
                if let display = displays.displays.display(at: CGPoint(x: frame.midX, y: frame.midY)) {
                    waitingOn.insert(display.id.storageKey)
                }
            }
            // The look stays on the displays the newcomers were first held on: one dragged elsewhere is not tiled there.
            if pinned == nil, !waitingOn.isEmpty { pinned = waitingOn }
            let groups = waitingOn.isEmpty ? request.groups.values.flatMap { $0 } : waitingOn.flatMap { request.groups[$0] ?? [] }
            var baseline: [(WindowRef, CGRect)] = []
            for ref in groups {
                if let frame = await windows.frame(of: ref) { baseline.append((ref, frame)) }
            }
            // No group there yet: the windows the newcomer would be tiled with stand in, so moving one by hand during
            // the wait calls the tile off.
            if groups.isEmpty {
                let ticket = windows.mutationContext.capture()
                for display in displays.displays where waitingOn.contains(display.id.storageKey) {
                    let peers = await windows.visibleWindowsCounted(
                        on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                        excluding: Set(model.settings.excludedBundleIDs), includingNewWindowsOf: request.pid,
                        keepingCoveredByNewcomer: true).found
                    baseline += peers.filter { !waiting.allowed.contains($0.window) }.map { ($0.window, $0.frame) }
                }
            }
            do { try await Task.sleep(for: .seconds(wait)) } catch { return (tiledAny, true, "cancelled") }
            for (window, frame) in baseline {
                guard let current = await windows.frame(of: window),
                      CommandExecutor.sameFrame(frame, current) else {
                    // Another app's tile moved these windows while this one waited: that is Tessera's doing, not a hand
                    // change. Baseline again and wait again, so the second app opened in a row is not dropped.
                    if ownMoveCount != movesBefore, ContinuousClock.now < deadline { continue waiting }
                    return (tiledAny, true, "groupChangedDuringWait")
                }
            }
            // Another app's tile can be moving right then (it answers notFound): try again briefly.
            var result = (JoinLook.notFound, "noWindowYet")
            for attempt in 0..<4 {
                var after = request
                after.waiting = waiting
                after.displaysOnly = pinned
                after.lastAttempt = attempt == 3
                result = await look(after)
                if result.0 != .notFound || attempt == 3 { break }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return (tiledAny, true, "cancelled") }
            }
            if result.0 == .tiled { tiledAny = true }
            if result.0 == .stopped { return (tiledAny, true, result.1) }
            guard case .held(let newcomers) = result.0 else { return (tiledAny, false, result.1) }
            waiting = (now: newcomers, allowed: waiting.allowed + newcomers)
        }
    }

    /// Whether `pid` has a minimised window (one Accessibility read, bounded by the usual timeout).
    private static func hasMinimisedWindow(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let windows = AX.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.contains { window in
            AXUIElementSetMessagingTimeout(window, 0.3)
            return AX.bool(window, kAXMinimizedAttribute) == true
        }
    }

    /// The display each of `ids` is on, from the window server's bounds (any layer, on or off screen).
    private static func displayKeys(of ids: Set<CGWindowID>, in topology: WindowTopology) -> [CGWindowID: String] {
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        var keys: [CGWindowID: String] = [:]
        for row in rows {
            guard let id = row[kCGWindowNumber as String] as? CGWindowID, ids.contains(id),
                  let bounds = (row[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) })
            else { continue }
            keys[id] = topology.key(containing: bounds)
        }
        return keys
    }

    /// Layer-0 windows of `pid` on screen now, from the window server (no Accessibility call).
    private static func onScreenWindows(of pid: pid_t) -> Set<CGWindowID> {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(rows.compactMap { row in
            guard row[kCGWindowOwnerPID as String] as? pid_t == pid, row[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return row[kCGWindowNumber as String] as? CGWindowID
        })
    }

    /// An app unhidden in the last few seconds brings back windows it already had; none of them is joining.
    private func wasUnhidden(_ pid: pid_t) -> Bool {
        unhidden = unhidden.filter { $0.value.timeIntervalSinceNow > -3 }
        return unhidden[pid] != nil
    }

    /// One line per look, so "it did not tile" has a reason in the log (`log show --predicate 'category == "split-decision"'`).
    private func logJoin(_ request: JoinRequest, bundleID: String?, outcome: String, reason: String) {
        decisionLog.notice("""
            join \(outcome, privacy: .public): \(reason, privacy: .public); trigger \(request.trigger, privacy: .public), \
            app \(bundleID ?? "?", privacy: .public), scope \(self.model.settings.splitNewWindowScope.rawValue, privacy: .public), \
            groups \(request.groups.count)
            """)
    }
}
