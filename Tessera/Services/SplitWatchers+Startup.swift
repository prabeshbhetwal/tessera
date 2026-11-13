import AppKit
import TesseraCore

extension SplitWatchers {
    func scheduleRestoration() {
        startupRestore?.cancel()
        let ticket = windows.mutationContext.capture()
        startupRestore = Task { [weak self] in
            await WindowMutationScope.$ticket.withValue(ticket) { await self?.restoreKnownGroups() }
            if !Task.isCancelled { self?.startupRestore = nil }
        }
    }

    func restoreKnownGroups() async {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        await WindowMutationScope.$ticket.withValue(ticket) { await restoreKnownGroups(ticket) }
    }

    private func restoreKnownGroups(_ ticket: WindowMutationContext.Ticket) async {
        let settings = model.settings
        guard settings.learnSplits, settings.splitTilesNewWindow else { return }
        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        for display in displays.displays {
            guard !Task.isCancelled, model.settings == settings,
                  Permissions.isAccessibilityTrusted, NSEvent.pressedMouseButtons == 0 else { return }
            guard ticket.topology.contains(display), windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true) else { continue }
            let found = await windows.visibleWindows(on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                                                     excluding: Set(model.settings.excludedBundleIDs))
            guard !Task.isCancelled, ownMoves == 0, model.settings == settings else { return }
            guard windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
                  displays.displays.contains(display) else { continue }
            // A valid manual arrangement is authoritative; startup only recovers stacked known groups.
            let overlaps = found.indices.contains { a in
                found.indices.contains { b in
                    a < b && found[a].frame.intersection(found[b].frame).width > 2
                        && found[a].frame.intersection(found[b].frame).height > 2
                }
            }
            guard overlaps else { continue }
            guard found.count > 1, let goals = model.settings.learnedFrames(for: found, display: display),
                  zip(found, goals).contains(where: { !CommandExecutor.sameFrame($0.0.frame, $0.1) }) else { continue }
            beginOwnMove()
            _ = await windows.moveTogether(Array(zip(found.map(\.window), goals)),
                                           primaryHeight: ticket.topology.primaryHeight, duration: model.glideSeconds)
            endOwnMove()
        }
    }

}
