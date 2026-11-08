import AppKit
import TesseraCore

/// A window opening beside a side-by-side group gets a place in it (`splitTilesNewWindow`): the group is tiled again
/// with the new window, in the learned split for the apps now there when there is one, otherwise in equal shares. A hand
/// adjustment afterwards is learned as usual, so the next time those apps meet they get it. One ⌃⌥Z puts them back.
///
/// Only the launched or activated app's windows count as joining, so a Space switch or an unhidden app never re-tiles
/// a display. `splitNewWindowScope` picks the displays: only ones whose windows already sat side by side (a watched
/// group), or also, for an app just launched, any display where the apps now there have a learned split.
extension SplitWatchers {
    /// The groups are read now, before anything awaits: the activation also re-arms the watchers (`Coordinator`), which
    /// stops a watch once a window overlaps it. A launch looks a few times, since its first window can take a while.
    func joinSoon(pid: pid_t, launched: Bool) {
        let settings = model.settings
        guard settings.learnSplits, settings.splitTilesNewWindow, pid != ProcessInfo.processInfo.processIdentifier
        else { return }
        let tiled = watchers.filter { !$0.value.watched.isEmpty }.mapValues(\.watched)
        let anywhere = launched && settings.splitNewWindowScope == .rememberedSplits
        guard !tiled.isEmpty || anywhere else { return }
        pendingJoin?.cancel()
        pendingJoin = Task { [weak self] in
            for delay in launched ? [500, 1000, 1500] : [500] {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                guard let self else { return }
                if await self.join(pid: pid, tiled: tiled, anywhere: anywhere) { return }
            }
        }
    }

    /// True once a group was tiled, or the setting went off.
    private func join(pid: pid_t, tiled: [String: [WindowRef]], anywhere: Bool) async -> Bool {
        let settings = model.settings
        guard settings.learnSplits, settings.splitTilesNewWindow, Permissions.isAccessibilityTrusted else { return true }
        guard ownMoves == 0 else { return false }
        var done = false
        for display in displays.displays {
            let watched = tiled[display.id.storageKey] ?? []
            guard !watched.isEmpty || anywhere else { continue }
            let found = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                     excluding: Set(settings.excludedBundleIDs))
            guard !Task.isCancelled, ownMoves == 0 else { return false }
            let joined = found.filter { $0.window.pid == pid && !watched.contains($0.window) }
            guard !joined.isEmpty, found.count > 1 else { continue }
            // The whole group is still here (same Space), so the new window joins it.
            let wasTiled = !watched.isEmpty && watched.allSatisfy { window in found.contains { $0.window == window } }
            guard wasTiled || anywhere else { continue }
            if await tileIn(found, joined: joined, display: display, wasTiled: wasTiled, settings: settings) { done = true }
        }
        return done
    }

    private func tileIn(_ found: [(window: WindowRef, frame: CGRect)], joined: [(window: WindowRef, frame: CGRect)],
                        display: DisplayContext, wasTiled: Bool, settings: TesseraSettings) async -> Bool {
        let ordered = onScreenOrder(found, portrait: display.range.isPortrait)
        let learned = settings.learnedFrames(for: ordered, display: display)
        guard wasTiled || learned != nil else { return false }
        let goals = learned ?? GridGeometry.tiles(ordered.count, display: display)
        let moves = ordered.indices.filter { !CommandExecutor.sameFrame(ordered[$0].frame, goals[$0]) }
        guard !moves.isEmpty else { return false }

        beginOwnMove()
        let (landed, undoMarker) = await windows.moveTogether(
            moves.map { (window: ordered[$0].window, goal: goals[$0]) }, primaryHeight: DisplayService.primaryHeight,
            duration: model.glideSeconds)
        endOwnMove()  // re-arms the watchers, which then watch the new group
        guard landed.contains(where: { $0 != nil }) else { return false }

        var finals = ordered
        for (index, frame) in zip(moves, landed) { if let frame { finals[index].frame = frame } }
        let kind = HelpEventKind.windowJoined(joined: joined.map { HelpEvent.appName($0.window) }, usedSplit: learned != nil)
        let split = learned == nil ? nil : SplitMemory.lookup(SplitKey(ordered, on: display), in: settings.learnedSplits)
        onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                           group: onScreenOrder(finals, portrait: display.range.isPortrait), split: split,
                           previous: nil, undoMarker: undoMarker))
        return true
    }
}
