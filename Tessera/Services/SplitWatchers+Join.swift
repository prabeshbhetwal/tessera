import AppKit
import TesseraCore

/// A window opening beside a side-by-side group gets a place in it (`splitTilesNewWindow`): the group is tiled again
/// with the new window, in the learned split for the apps now there when there is one, otherwise in equal shares. A hand
/// adjustment afterwards is learned as usual, so the next time those apps meet they get it. One ⌃⌥Z puts them back.
/// Equal shares wait `splitNewWindowWait` seconds and apply only if the window is still open then.
///
/// Only the launched or activated app's windows count as joining, so a Space switch or an unhidden app never re-tiles
/// a display. `splitNewWindowScope` picks the displays: only ones whose windows already sat side by side (a watched
/// group), or also, for an app just launched, any display where the apps now there have a learned split. A window
/// restored after the rest covered its space (`minimiseFillsGap`) joins the windows it left the same way.
extension SplitWatchers {
    /// The groups are read now, before anything awaits: the activation also re-arms the watchers (`Coordinator`), which
    /// stops a watch once a window overlaps it. A launch looks a few times, since its first window can take a while.
    /// `restoring` is set for a window restored after the rest covered its space (`MinimisedWindows`): it joins the
    /// windows it left, even when only one of them is left there (a lone window isn't watched).
    func joinSoon(pid: pid_t, launched: Bool, windowCreated: Bool = false, createdWindowID: CGWindowID? = nil,
                  restoring: (others: [WindowRef], displayKey: String)? = nil) {
        let settings = model.settings
        let ticket = windows.mutationContext.capture()
        guard settings.learnSplits, settings.splitTilesNewWindow || restoring != nil, pid != ProcessInfo.processInfo.processIdentifier
        else { return }
        // An app relaunched after quitting out of a group (the rest covered its space) comes back to the windows it left.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let contexts = bundleID.flatMap { closedOutOf[$0] } ?? [:]
        let restored = restoring != nil || !contexts.isEmpty
        // A just-launched or restored app activates too: keep that look (its retries, groups and scope).
        if !launched, !restored, !windowCreated, firstWindowLooks.contains(pid) { return }
        var tiled = watchers.filter { !$0.value.watched.isEmpty }.mapValues(\.watched)
        for (display, others) in contexts where tiled[display] == nil { tiled[display] = others }
        if let restoring, tiled[restoring.displayKey] == nil { tiled[restoring.displayKey] = restoring.others }
        let anywhere = (launched || windowCreated) && settings.splitNewWindowScope == .rememberedSplits
        guard !tiled.isEmpty || anywhere else { return }
        if let createdWindowID { pendingNewWindows[pid, default: []].insert(createdWindowID) }
        let existing = !launched ? lifecycle.windowIDs(pid).subtracting(pendingNewWindows[pid] ?? []) : []
        pendingJoins[pid]?.cancel()
        if launched || restored || windowCreated { firstWindowLooks.insert(pid) } else { firstWindowLooks.remove(pid) }
        pendingJoins[pid] = Task { [weak self] in
            // A replaced look leaves the bookkeeping to the look that replaced it.
            defer {
                if !Task.isCancelled {
                    self?.pendingJoins[pid] = nil
                    self?.firstWindowLooks.remove(pid)
                    self?.pendingNewWindows[pid] = nil
                }
            }
            await WindowMutationScope.$ticket.withValue(ticket) {
                // An activated app's window can show late too (an Electron window shown from the Dock), so every look
                // retries. A cold launch can take several seconds to show its first window (WhatsApp, Wispr Flow, Dia), so
                // a launch looks for 12 s.
                let wait = restored ? 0 : settings.splitNewWindowWaitSeconds
                for delay in (launched || windowCreated) ? [500, 1000, 1500, 2000, 2000, 2000, 3000] : [500, 1000, 1500] {
                    do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                    guard let self else { return }
                    if !launched, restoring == nil, !windowCreated, self.wasUnhidden(pid) { return }
                    switch await self.join(pid: pid, tiled: tiled, anywhere: anywhere, restored: restored, holds: wait > 0,
                                           existing: existing, restoringMinimised: restoring != nil) {
                    case .tiled: return
                    case .notFound: continue
                    case .held(let first):
                        // No learned split for these apps: only a window still open after the wait is tiled in, so one
                        // opened for a moment (Wispr Flow, Finder) is left alone. A window the app opens during the wait
                        // waits its own turn.
                        var waiting = (now: first, allowed: first)
                        while true {
                            // Only the groups on the displays the newcomers wait on: a hand change to a split on
                            // another display must not cancel this join.
                            var baseline: [(WindowRef, CGRect)] = []
                            var waitingOn = Set<String>()
                            for ref in waiting.allowed {
                                guard let frame = await self.windows.frame(of: ref) else { continue }
                                baseline.append((ref, frame))
                                if let display = self.displays.displays.display(at: CGPoint(x: frame.midX, y: frame.midY)) {
                                    waitingOn.insert(display.id.storageKey)
                                }
                            }
                            let groups = waitingOn.isEmpty ? tiled.values.flatMap { $0 } : waitingOn.flatMap { tiled[$0] ?? [] }
                            for ref in groups {
                                if let frame = await self.windows.frame(of: ref) { baseline.append((ref, frame)) }
                            }
                            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                            for (window, frame) in baseline {
                                guard let current = await self.windows.frame(of: window),
                                      CommandExecutor.sameFrame(frame, current) else { return }
                            }
                            // Another app's tile can be moving right then (it answers notFound): try again briefly.
                            var look = JoinLook.notFound
                            for attempt in 0..<4 {
                                look = await self.join(pid: pid, tiled: tiled, anywhere: anywhere, restored: restored,
                                                       holds: false, waiting: waiting, existing: existing,
                                                       restoringMinimised: restoring != nil)
                                if look != .notFound || attempt == 3 { break }
                                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                            }
                            guard case .held(let newcomers) = look else { return }
                            waiting = (now: newcomers, allowed: waiting.allowed + newcomers)
                        }
                    }
                }
            }
        }
    }

    enum JoinLook: Equatable { case tiled, held([WindowRef]), notFound }

    /// An app unhidden in the last few seconds brings back windows it already had; none of them is joining.
    private func wasUnhidden(_ pid: pid_t) -> Bool {
        unhidden = unhidden.filter { $0.value.timeIntervalSinceNow > -3 }
        return unhidden[pid] != nil
    }

    /// `.tiled` once a group was tiled, or the setting went off. `holds` leaves a window whose group has no learned split
    /// untiled and answers `.held` with it (see `splitNewWindowWait`); a hold anywhere wins, so it is looked at again.
    /// `waiting` (after the wait) tiles only where a window that waited (`now`) is still open, and leaves out any window
    /// the app opened since (not in `allowed`), answering `.held` with those so they wait their own turn.
    private func join(pid: pid_t, tiled: [String: [WindowRef]], anywhere: Bool, restored: Bool, holds: Bool,
                      waiting: (now: [WindowRef], allowed: [WindowRef])? = nil,
                      existing: Set<CGWindowID> = [], restoringMinimised: Bool = false) async -> JoinLook {
        let settings = model.settings
        guard settings.learnSplits, settings.splitTilesNewWindow || restoringMinimised, Permissions.isAccessibilityTrusted else { return .tiled }
        guard ownMoves == 0 else { return .notFound }
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        var done = false, held: [WindowRef] = []
        for display in displays.displays {
            guard ticket.topology.contains(display), windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true) else { continue }
            let watched = tiled[display.id.storageKey] ?? []
            guard !watched.isEmpty || anywhere else { continue }
            var found = await windows.visibleWindows(on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                                                     excluding: Set(settings.excludedBundleIDs), retaining: watched,
                                                     includingNewWindowsOf: pid, existingWindowIDs: existing)
            guard !Task.isCancelled, ownMoves == 0 else { return .notFound }
            guard windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
                  displays.displays.contains(display) else { continue }
            var joined = found.filter { $0.window.pid == pid && !watched.contains($0.window)
                && !($0.window.windowID.map { existing.contains($0) } ?? false) }
            guard !joined.isEmpty, found.count > 1 || (restored && found.count == 1) else { continue }
            if let waiting {
                let newcomers = joined.map(\.window).filter { !waiting.allowed.contains($0) }
                held += newcomers
                guard joined.contains(where: { waiting.now.contains($0.window) }) else { continue }
                found.removeAll { newcomers.contains($0.window) }
                joined.removeAll { newcomers.contains($0.window) }
            }
            // The whole group is still here (same Space), so the new window joins it. A restored window rejoins what is
            // left of the group it was minimised out of, even if some of it closed since.
            let present = watched.filter { window in found.contains { $0.window == window } }
            let wasTiled = (!present.isEmpty && (restored || present.count == watched.count))
                || (restored && found.count == 1 && joined.count == 1)
            guard wasTiled || anywhere else { continue }
            if holds, wasTiled,
               settings.learnedFrames(for: onScreenOrder(found, portrait: display.range.isPortrait), display: display) == nil {
                held += joined.map(\.window)
                continue
            }
            if await tileIn(found, joined: joined, display: display, wasTiled: wasTiled, restored: restored,
                            settings: settings) { done = true }
        }
        return !held.isEmpty ? .held(held) : done ? .tiled : .notFound
    }

    private func tileIn(_ found: [(window: WindowRef, frame: CGRect)], joined: [(window: WindowRef, frame: CGRect)],
                        display: DisplayContext, wasTiled: Bool, restored: Bool, settings: TesseraSettings) async -> Bool {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        guard windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
              ticket.topology.contains(display), displays.displays.contains(display) else { return false }
        let ordered = onScreenOrder(found, portrait: display.range.isPortrait)
        let learned = settings.learnedFrames(for: ordered, display: display)
        guard wasTiled || learned != nil else { return false }
        let goals = learned ?? GridGeometry.tiles(ordered.count, display: display)
        let moves = ordered.indices.filter { !CommandExecutor.sameFrame(ordered[$0].frame, goals[$0]) }
        // Already in its place (an app reopening a window where it was last tiled): nothing moves, so no move's end
        // re-arms the watchers. Re-arm here, or the group is watched without it and its close leaves a gap.
        guard !moves.isEmpty else {
            watch(ordered, display: display)
            consumeJoinContext(joined.map(\.window), displayKey: display.id.storageKey)
            armSoon(after: .zero)
            return true
        }

        watch(Array(zip(ordered.map(\.window), goals)), display: display)
        beginOwnMove()
        // The whole group, so the windows beside one that lands short of its goal (System Settings is a fixed width)
        // follow its real edge instead of leaving a hole beside it.
        let (landed, undoMarker) = await windows.moveTogether(
            ordered.indices.map { (window: ordered[$0].window, goal: goals[$0]) },
            primaryHeight: ticket.topology.primaryHeight, duration: model.glideSeconds, gap: display.profile.gap)
        endOwnMove()  // re-arms the watchers, which then watch the new group
        guard !Task.isCancelled, windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
              displays.displays.contains(display) else { return false }

        var finals = ordered
        for (index, frame) in landed.enumerated() { if let frame { finals[index].frame = frame } }
        let exact = moves.filter { index in landed[index].map { CommandExecutor.sameFrame($0, goals[index]) } ?? false }
        if watchers[display.id.storageKey]?.watches(finals) == true {
            watch(finals, display: display)
        }
        // Only a join every moving window accepted uses up the reopen context; a refusal leaves it for a retry.
        if moves.allSatisfy({ landed[$0] != nil }) {
            consumeJoinContext(joined.map(\.window), displayKey: display.id.storageKey)
        }
        guard moves.contains(where: { landed[$0] != nil }) else { return false }
        let kind: HelpEventKind = if exact.count < moves.count {
            .tilePartial(moved: exact.count, total: moves.count,
                         stuck: moves.filter { !exact.contains($0) }.map { HelpEvent.appName(ordered[$0].window) })
        } else {
            .windowJoined(joined: joined.map { HelpEvent.appName($0.window) }, usedSplit: learned != nil, restored: restored)
        }
        let split = learned == nil ? nil : SplitMemory.lookup(SplitKey(ordered, on: display), in: settings.learnedSplits)
        onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                           group: onScreenOrder(finals, portrait: display.range.isPortrait), split: split,
                           previous: nil, undoMarker: undoMarker))
        return true
    }
}
