import AppKit
import TesseraCore

/// Owns the coach. Keeps the last few help events in a journal, asks `CoachPolicy` whether a card appears on its own,
/// opens the latest event on request (⌃⌥/, the menu bar, `tessera explain`) and runs the card's buttons
/// (`HelpCenter+Actions`).
///
/// Events can arrive from inside Tessera's own moves (the split watcher's reflow), so recording one only ever puts a
/// card on screen. Every window move or split change runs later, in a `Task`.
@MainActor
final class HelpCenter {
    /// The event on the card, its steps, and which step is showing.
    struct Tour {
        var event: HelpEvent
        var steps: [CoachStep]
        var index = 0
        var presentation: CoachPresentation
        var keyable: Bool

        var step: CoachStep { steps[index] }
    }

    let model: SettingsModel
    let executor: CommandExecutor
    let presenter: WindowPresenter
    let showHUD: (String) -> Void
    private let displays: DisplayService
    private let isRingOpen: () -> Bool
    private let coach = CoachController()
    /// Also written by a forget from the card (`HelpCenter+Actions`), so ⌃⌥/ and ‹ › can explain it later.
    var journal = HelpJournal()
    private var policy = CoachPolicy()
    private(set) var tour: Tour?
    /// Bumped by every show and close, so an action that awaited the display's windows never acts on a newer card.
    private(set) var generation = 0

    init(model: SettingsModel, displays: DisplayService, executor: CommandExecutor, presenter: WindowPresenter,
         showHUD: @escaping (String) -> Void, isRingOpen: @escaping () -> Bool) {
        self.model = model
        self.displays = displays
        self.executor = executor
        self.presenter = presenter
        self.showHUD = showHUD
        self.isRingOpen = isRingOpen
        coach.onAction = { [weak self] in self?.perform($0) }
        coach.onClose = { [weak self] in self?.close() }
        coach.onBrowse = { [weak self] in self?.browse($0) }
        coach.onDontShow = { [weak self] in
            self?.updateHelp { $0.autoShow = false }
            self?.close()
        }
    }

    /// Journals `event` and shows the coach when `CoachPolicy` says so. A learn for the windows a "try it" step waits
    /// on moves that tour on instead.
    func record(_ event: HelpEvent) {
        if let tour, tour.step.waitsForLearn, case .splitLearned = event.kind, event.key == tour.event.key,
           tour.index + 1 < tour.steps.count {
            var next = tour
            // Where the windows ended up, and the split the learn replaced: the next step's Undo restores it.
            next.event.apps = event.apps
            next.event.frames = event.frames
            next.event.split = event.split
            next.event.previousSplit = event.previousSplit
            next.index += 1
            journal.record(event)
            // The tour just explained this learn and the neighbours following; neither shows again on its own.
            if !tour.keyable {
                let moments = [CoachMoment.splitLearned, .neighboursFollowed].map(\.rawValue)
                updateHelp { $0.seenMoments.formUnion(moments) }
            }
            show(next)
            return
        }
        journal.record(event)
        guard display(for: event) != nil else { return }
        let context = CoachContext(
            ringOpen: isRingOpen(), mouseDown: NSEvent.pressedMouseButtons != 0,
            secondsSinceTyping: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            coachShowing: coach.isShowing, now: Date())
        let previousTile = event.key.flatMap { journal.lastTile(for: $0, before: event.id) }
        guard let presentation = policy.presentation(for: event, help: model.settings.help,
                                                      previousTile: previousTile, context: context) else { return }
        let moment = event.moment.rawValue
        updateHelp { $0.seenMoments.formUnion([moment]) }
        show(Tour(event: event, steps: steps(for: event), presentation: dimmed(presentation), keyable: false))
    }

    /// What Just Happened?: the latest event, opened on request.
    func explainLatest() {
        guard let event = journal.latest else {
            showHUD("Nothing to explain yet")
            return
        }
        open(event)
    }

    // MARK: Showing

    /// `event` from its first step, on request: the card takes the keyboard and ‹ › browse the journal.
    private func open(_ event: HelpEvent) {
        guard display(for: event) != nil else {
            showHUD("That display isn't connected now")
            return
        }
        show(Tour(event: event, steps: steps(for: event), presentation: dimmed(.full), keyable: true))
    }

    private func browse(_ delta: Int) {
        guard let id = tour?.event.id,
              let event = delta < 0 ? journal.event(before: id) : journal.event(after: id) else { return }
        open(event)
    }

    /// `.light` when Settings › General › Tips › Dim the screen behind tips is off.
    /// The drag tour needs both learning and neighbour resizing; without either the drag could never finish it.
    func steps(for event: HelpEvent) -> [CoachStep] {
        let s = model.settings
        return CoachScript.steps(for: event, dragTour: s.learnSplits && s.splitReflowsNeighbours)
    }

    func dimmed(_ presentation: CoachPresentation) -> CoachPresentation {
        model.settings.help.dimScreen ? presentation : .light
    }

    /// Puts the tour's current step on its event's display. When that display has gone, the card closes instead.
    func show(_ tour: Tour) {
        guard let display = display(for: tour.event) else {
            close()
            return
        }
        self.tour = tour
        generation += 1
        var presentation = tour.presentation
        var theme = model.settings.activeTheme
        // With the dim off, a "try it" step still needs its pulsing seam: a clear dim draws only that.
        if tour.step.spotlight == .seam, !model.settings.help.dimScreen {
            presentation = .full
            theme.preview.dimStrength = 0
        }
        coach.present(step: tour.step, index: tour.index, count: tour.steps.count, event: tour.event,
                      display: display, presentation: presentation, keyable: tour.keyable, theme: theme)
    }

    func close() {
        tour = nil
        generation += 1
        coach.dismiss()
    }

    /// Settings writes run `Coordinator.settingsChanged` at once. `record` can be called in the middle of a watcher's
    /// reflow, so every write from here waits for the next turn of the main actor.
    func updateHelp(_ change: @escaping @MainActor (inout HelpSettings) -> Void) {
        Task { @MainActor [model] in change(&model.settings.help) }
    }

    private func display(for event: HelpEvent) -> DisplayContext? {
        displays.displays.first { $0.id.storageKey == event.displayKey }
    }
}
