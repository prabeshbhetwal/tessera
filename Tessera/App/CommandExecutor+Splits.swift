import AppKit
import os
import TesseraCore

/// Learned splits (spec: Tile reuses a remembered arrangement): choosing Tile's frames, watching the result for
/// hand adjustments, and the Remember Split command.
extension CommandExecutor {
    /// The display `selector` names and the visible windows on it. `.current` is the front window's display; with
    /// no front window (desktop or Tessera in front) the display under the cursor.
    func windowsOnDisplay(_ selector: DisplaySelector) async throws(Failure)
        -> (display: DisplayContext, found: [(window: WindowRef, frame: CGRect)]) {
        guard Permissions.isAccessibilityTrusted else {
            throw Failure(message: "Tessera needs Accessibility permission to move windows")
        }
        let front = await windows.frontmostWindow()
        let frontFrame: CGRect? = if let front { await windows.frame(of: front) } else { nil }
        let display = try resolve(selector == .current && frontFrame == nil ? .cursor : selector, windowFrame: frontFrame)
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        let found = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                 excluding: Set(model.settings.excludedBundleIDs))
        guard windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
              displays.displays.contains(display) else { throw Failure(message: "Display or Space changed; try again") }
        return (display, found)
    }

    /// The frames Tile gives `ordered`: the remembered split for these apps on this display when there is one that
    /// fits, otherwise equal tiles.
    func splitFrames(for ordered: [(window: WindowRef, frame: CGRect)], display: DisplayContext)
        -> (frames: [CGRect], learned: Bool) {
        if let frames = model.settings.learnedFrames(for: ordered, display: display) { return (frames, true) }
        return (GridGeometry.tiles(ordered.count, display: display), false)
    }

    /// Saves how the windows on the display are arranged now, then watches them; Tile reuses the split.
    func rememberSplit(_ selector: DisplaySelector) async throws(Failure) -> CommandResult {
        let (display, found) = try await windowsOnDisplay(selector)
        switch splitWatcher.save(found, display: display) {
        case let .failure(rejection):
            throw Failure(message: rejection.message)
        case let .success((key, _)):
            splitWatcher.watch(found, display: display)
            return CommandResult(ok: true, message: "Remembered split · \(SplitLabel.apps(key)) · "
                + SplitLabel.display(key, displays: [display]))
        }
    }

    /// Forgets the learned split for the apps on the display now.
    func forgetSplit(_ selector: DisplaySelector, source: CommandSource) async throws(Failure) -> CommandResult {
        let (display, found) = try await windowsOnDisplay(selector)
        let key = SplitKey(found, on: display)
        guard let previous = SplitMemory.lookup(key, in: model.settings.learnedSplits) else {
            throw Failure(message: "No split for these apps")
        }
        // A learn still pending from an earlier adjustment must not re-save the split just forgotten.
        splitWatcher.stop()
        model.settings.learnedSplits = SplitMemory.forget(key, in: model.settings.learnedSplits)
        splitWatcher.armSoon()
        onEvent?(.make(kind: .splitForgotten, source: source, display: display,
                       group: onScreenOrder(found, portrait: display.range.isPortrait), split: nil,
                       previous: previous))
        return CommandResult(ok: true, message: "Forgot split · \(SplitLabel.apps(key))")
    }

    /// Every visible window on the display, side by side: in the display's learned split for those apps when there is
    /// one, otherwise in equal shares (3 windows get a third each). Windows keep their left-to-right order
    /// (top-to-bottom on a portrait display) unless the split restores its own. One ⌃⌥Z undoes the lot.
    /// `evenly` always uses equal shares and its watch never learns, so the learned split survives for the next Tile.
    func tile(_ selector: DisplaySelector, evenly: Bool, source: CommandSource) async throws(Failure) -> CommandResult {
        guard !tiling else { throw Failure(message: "Already tiling") }
        tiling = true
        defer { tiling = false }
        let (display, found) = try await windowsOnDisplay(selector)
        let original = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        guard let ticket = windows.mutationContext.overridingLayouts(original, on: [display.id.storageKey]) else {
            throw Failure(message: "Display or Space changed; try again")
        }
        splitWatcher.explicitLayout(on: [display.id.storageKey], ticket: ticket)
        splitWatcher.relinquish([display.id.storageKey], windows: found.map(\.window))
        do {
            return try await WindowMutationScope.$ticket.withValue(ticket) {
                try await tileOnDisplay(display, found: found, evenly: evenly, source: source)
            }
        } catch let error as Failure { throw error }
        catch { throw Failure(message: "Tiling interrupted; try again") }
    }

    private func tileOnDisplay(_ display: DisplayContext, found: [(window: WindowRef, frame: CGRect)],
                               evenly: Bool, source: CommandSource) async throws(Failure) -> CommandResult {
        guard !found.isEmpty else { throw Failure(message: "No windows to tile on this display") }
        let portrait = display.range.isPortrait
        let ordered = onScreenOrder(found, portrait: portrait)
        // An earlier Tile's watch would learn adjustments made after this one.
        let (slots, learned) = evenly
            ? (GridGeometry.tiles(ordered.count, display: display), false)
            : splitFrames(for: ordered, display: display)
        let alreadyThere = learned && zip(ordered, slots).allSatisfy { Self.sameFrame($0.frame, $1) }
        splitWatcher.watch(Array(zip(ordered.map(\.window), slots)), display: display, learns: !evenly)
        // All at once, so with a snap speed set the windows glide together instead of one after another.
        let batch = await windows.newBatch()
        let landed = await withTaskGroup(of: (Int, CGRect?).self) { group in
            for (index, (entry, slot)) in zip(ordered, slots).enumerated() {
                group.addTask {
                    let result = await self.place(entry.window, current: entry.frame, goal: slot, batch: batch, manual: false)
                    if case let .applied(frame) = result { return (index, frame) }
                    return (index, nil)
                }
            }
            var results = [CGRect?](repeating: nil, count: ordered.count)
            for await (index, frame) in group { results[index] = frame }
            return results
        }
        let cancelled = await windows.isBatchCancelled(batch)
        let undoMarker = await windows.mergeMoves(batch)
        guard !cancelled, !Task.isCancelled else { throw Failure(message: "Tiling cancelled by Undo") }
        if let ticket = WindowMutationScope.ticket {
            guard windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
                  displays.displays.contains(display) else { throw Failure(message: "Tiling cancelled after a display or Space change") }
        }
        // After the moves, so their settling is already ignored.
        let actual = ordered.indices.map { (window: ordered[$0].window, frame: landed[$0] ?? ordered[$0].frame) }
        splitWatcher.watch(actual, display: display, learns: !evenly)
        let n = ordered.count
        let moved = ordered.indices.filter { index in
            landed[index].map { Self.sameFrame($0, slots[index]) } ?? false
        }.count
        let split = SplitMemory.lookup(SplitKey(ordered, on: display), in: model.settings.learnedSplits)
        let kind: HelpEventKind = if moved < n {
            .tilePartial(moved: moved, total: n,
                         stuck: ordered.indices.filter { index in
                             !(landed[index].map { Self.sameFrame($0, slots[index]) } ?? false)
                         }.map { HelpEvent.appName(ordered[$0].window) })
        } else if evenly {
            .tiledEvenly(hasSplit: split != nil)
        } else {
            .tiled(usedSplit: learned)
        }
        // A split that restores its own order can land the windows in a different order from `ordered`.
        let after = onScreenOrder(ordered.indices.map { (window: ordered[$0].window, frame: landed[$0] ?? ordered[$0].frame) },
                                  portrait: display.range.isPortrait)
        onEvent?(.make(kind: kind, source: source, display: display, group: after, split: split, previous: nil,
                       undoMarker: undoMarker))
        Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "tiling")
            .notice("Tile finished: \(n) exposed windows, \(moved) placed as requested, learned split: \(learned)")
        if alreadyThere, moved == n {
            return CommandResult(ok: true, message: "Already in your split · Tile Evenly for equal shares")
        }
        let message = moved == n ? "Tiled \(n) window\(n == 1 ? "" : "s")" : "Tiled \(moved) of \(n) windows"
        return CommandResult(ok: moved > 0, message: message + (learned ? " · your split" : evenly ? " evenly" : "")
                             + (moved < n ? " · some apps limited or refused their size" : ""))
    }

    func undoLast() async throws(Failure) {
        splitWatcher.cancelPendingWork()
        // Bracketed so the restore is never read as a hand adjustment; its end re-arms the watchers.
        splitWatcher.beginOwnMove()
        let undone = await windows.undoLast()
        splitWatcher.endOwnMove()
        guard undone else { throw Failure(message: "Nothing to undo") }
    }
}
