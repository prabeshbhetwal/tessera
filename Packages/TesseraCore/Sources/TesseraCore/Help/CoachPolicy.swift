import Foundation

public enum CoachPresentation: Equatable, Sendable { case full, light }

public struct CoachContext: Sendable {
    public var ringOpen: Bool, mouseDown: Bool, secondsSinceTyping: Double, coachShowing: Bool, now: Date
    public init(ringOpen: Bool, mouseDown: Bool, secondsSinceTyping: Double, coachShowing: Bool, now: Date) {
        self.ringOpen = ringOpen
        self.mouseDown = mouseDown
        self.secondsSinceTyping = secondsSinceTyping
        self.coachShowing = coachShowing
        self.now = now
    }
}

/// Decides whether the coach appears by itself after an action, and how loudly.
public struct CoachPolicy: Sendable {
    /// Reason string → when it was last let through, so the same non-event reason shows once a day.
    private var reasonShownAt: [String: Date] = [:]

    public init() {}

    /// nil = don't show on its own. Records per-day non-event reasons it lets through.
    public mutating func presentation(for event: HelpEvent, help: HelpSettings,
                                      previousTile: HelpEvent?, context: CoachContext) -> CoachPresentation? {
        guard event.source.isInteractive, help.autoShow else { return nil }
        guard !(context.ringOpen || context.mouseDown || context.coachShowing) else { return nil }
        if event.source == .hand, context.secondsSinceTyping < 2 { return nil }

        if !help.seenMoments.contains(event.moment.rawValue) {
            if event.isNonEvent {
                recordReason(event, now: context.now)
                return .light
            }
            return .full
        }

        switch event.kind {
        case .tilePartial:
            return .light
        case .splitNotLearned(let reason):
            if let last = reasonShownAt[reason], Calendar.current.isDate(last, inSameDayAs: context.now) { return nil }
            reasonShownAt[reason] = context.now
            return .light
        case .tiled(let used):
            if case .tiled(let before)? = previousTile?.kind, before == !used { return .light }
            return nil
        default:
            return nil
        }
    }

    private mutating func recordReason(_ event: HelpEvent, now: Date) {
        if case .splitNotLearned(let reason) = event.kind { reasonShownAt[reason] = now }
    }
}
