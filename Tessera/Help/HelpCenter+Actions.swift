import AppKit
import TesseraCore

/// A display and the visible windows on it, as `CommandExecutor.windowsOnDisplay` reads them.
private typealias DisplayWindows = (display: DisplayContext, found: [(window: WindowRef, frame: CGRect)])

/// The coach card's buttons. Anything that moves windows or changes a split first reads the event's display: when it no
/// longer holds the event's apps, or an Undo would no longer reverse what the card describes, the card says so and
/// nothing changes.
extension HelpCenter {
    func perform(_ action: CoachAction) {
        guard let tour else { return }
        switch action {
        case .next:
            guard tour.index + 1 < tour.steps.count else { return close() }
            var next = tour
            next.index += 1
            // From the light card this expands into the full coach: the seam a "try it" step points at is in the dim.
            next.presentation = dimmed(.full)
            show(next)
        case .done:
            close()
        case .skip:
            // Skip only appears on a "try it" step. The steps after it report what the drag did, so with no drag they
            // would be untrue (and their Undo would restore the wrong split): the tour ends.
            close()
        case .openSplitsSettings:
            close()
            presenter.showSettings(pane: .splits)
        case .tileEvenly, .tileAll, .undoMove, .forgetSplit, .undoSplitChange:
            let generation = self.generation
            Task {
                let current = try? await executor.windowsOnDisplay(.id(tour.event.displayKey))
                var undoMarker: Int?
                if action == .undoMove { undoMarker = await executor.windows.undoMarker() }
                // The card closed or moved on while the windows were read; the click belonged to a card that's gone.
                guard generation == self.generation else { return }
                guard let current, tour.event.stillMatches(SplitKey(current.found, on: current.display)),
                      undoes(action, event: tour.event, undoMarker: undoMarker) else {
                    return showChanged(tour)
                }
                await run(action, event: tour.event, current: current)
            }
        }
    }

    /// An Undo reverses only what the card describes: the window history's latest step is still the event's own (a
    /// later move anywhere, or ‹ › to an older card, would otherwise undo something else), or the stored split is still
    /// the one the event left. Other actions need nothing more than the windows check.
    private func undoes(_ action: CoachAction, event: HelpEvent, undoMarker: Int?) -> Bool {
        switch action {
        case .undoMove:
            return event.undoMarker != nil && undoMarker == event.undoMarker
        case .undoSplitChange:
            guard let key = event.key else { return false }
            return SplitMemory.lookup(key, in: model.settings.learnedSplits) == event.split
        default:
            return true
        }
    }

    /// Runs a checked action. Commands go through `CommandBridge` as `.coach`: journalled, never coached. Called from
    /// a button's `Task`, never from `record`, so its settings writes don't land inside a reflow.
    private func run(_ action: CoachAction, event: HelpEvent, current: DisplayWindows) async {
        let display = DisplaySelector.id(event.displayKey)
        switch action {
        case .tileEvenly:
            await execute(.tileEvenly(display: display))
        case .tileAll:
            await execute(.tileWindows(display: display))
        case .undoMove:
            await execute(.undo)
        case .forgetSplit:
            forget(event, current: current)
        case .undoSplitChange:
            guard let key = event.key else { return }
            changeSplits { SplitMemory.restore(event.previousSplit, for: key, in: $0) }
            await execute(.tileWindows(display: display))
        case .next, .done, .skip, .openSplitsSettings:
            break
        }
    }

    /// Closes the card, then runs `command` as the menu bar does: the HUD shows its message, or why it failed.
    private func execute(_ command: Command) async {
        close()
        let result = await CommandBridge.execute(command, source: .coach)
        if let message = result.ok ? result.message : (result.message ?? "Command failed") { showHUD(message) }
    }

    /// Forgets the event's own split key, not whatever the display holds now, so ‹ › never forgets the wrong split.
    /// Then shows what that did, with an Undo that puts the split back.
    private func forget(_ event: HelpEvent, current: DisplayWindows) {
        guard let key = event.key, let tour else { return }
        let previous = SplitMemory.lookup(key, in: model.settings.learnedSplits)
        changeSplits { SplitMemory.forget(key, in: $0) }
        let forgotten = HelpEvent.make(
            kind: .splitForgotten, source: .coach, display: current.display,
            group: onScreenOrder(current.found, portrait: current.display.range.isPortrait), split: nil,
            previous: previous)
        journal.record(forgotten)
        show(Tour(event: forgotten, steps: [CoachScript.forgotten(forgotten)], presentation: tour.presentation,
                  keyable: tour.keyable))
    }

    /// Edits the learned splits with the watchers stopped, so a learn still pending from an earlier drag can't re-save
    /// what was just changed; they re-arm once it's done.
    private func changeSplits(_ change: ([LearnedSplit]) -> [LearnedSplit]) {
        executor.splitWatcher.stop()
        model.settings.learnedSplits = change(model.settings.learnedSplits)
        executor.splitWatcher.armSoon()
    }

    /// The display no longer holds the event's apps: say so and offer only Done. Light, because the spotlight would
    /// outline where the windows used to be.
    private func showChanged(_ tour: Tour) {
        var changed = tour
        changed.steps[tour.index].body = CoachScript.changed
        changed.steps[tour.index].actions = [.done]
        changed.presentation = .light
        show(changed)
    }
}
