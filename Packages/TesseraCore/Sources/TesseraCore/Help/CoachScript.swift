import Foundation

public enum CoachAction: Equatable, Sendable {
    case next, done, skip, tileEvenly, undoSplitChange, forgetSplit, undoMove, openSplitsSettings, tileAll

    public var label: String {
        switch self {
        case .next: "Show Me More"
        case .done: "Done"
        case .skip: "Skip"
        case .tileEvenly: "Tile Evenly Instead"
        case .undoSplitChange, .undoMove: "Undo"
        case .forgetSplit: "Forget This Split"
        case .openSplitsSettings: "Open Splits Settings"
        case .tileAll: "Tile All Windows"
        }
    }
}

public enum CoachSpotlight: Equatable, Sendable { case windows, seam }

public struct CoachStep: Equatable, Sendable {
    public var title: String
    public var body: String
    /// The first action is the primary (accent) button.
    public var actions: [CoachAction]
    public var spotlight: CoachSpotlight
    /// Advance when a `.splitLearned` for the same key arrives.
    public var waitsForLearn: Bool

    public init(
        title: String,
        body: String,
        actions: [CoachAction],
        spotlight: CoachSpotlight = .windows,
        waitsForLearn: Bool = false
    ) {
        self.title = title
        self.body = body
        self.actions = actions
        self.spotlight = spotlight
        self.waitsForLearn = waitsForLearn
    }
}

public enum CoachScript {
    /// Shown instead of running an action when the display no longer holds the event's apps.
    public static let changed = "These windows have changed since then."

    /// `dragTour` false (learning or neighbour resizing is off) leaves out the "drag this edge" steps for a Tile:
    /// a drag would neither move the neighbours nor teach a split, so the step could never finish.
    public static func steps(for event: HelpEvent, dragTour: Bool = true) -> [CoachStep] {
        let apps = event.apps
        let n = apps.count
        let followers = CoachCopy.list(Array(apps.dropFirst()))
        switch event.kind {
        case .tiled(let usedSplit):
            let first: CoachStep
            if usedSplit, let split = event.split {
                let shares = CoachCopy.shares(apps: apps, frames: event.frames, usable: event.usable, portrait: event.portrait)
                first = CoachStep(
                    title: "Tiled with your split",
                    body: "You taught Tessera this split for \(CoachCopy.list(apps)) on \(CoachCopy.day(split.updated)): \(shares). Without it, each would get \(CoachCopy.equalShare(n)).",
                    actions: [.next, .tileEvenly, .done])
            } else {
                first = CoachStep(
                    title: "Tiled in equal shares",
                    body: "Tessera has no split for \(CoachCopy.list(apps)) on \(event.displayName) yet, so each got \(CoachCopy.equalShare(n)).",
                    actions: [.next, .done])
            }
            guard n >= 2 else {
                var only = first
                only.actions = [.done]
                return [only]
            }
            guard dragTour else {
                var only = first
                only.actions.removeAll { $0 == .next }
                return [only]
            }
            let saved = (usedSplit && event.split != nil) ? "your new split" : "your split"
            return [
                first,
                CoachStep(
                    title: "Try it: drag this edge",
                    body: "Make \(apps[0]) \(event.portrait ? "shorter" : "narrower"). \(followers) will move with it.",
                    actions: [.skip], spotlight: .seam, waitsForLearn: true),
                CoachStep(
                    title: "\(followers) followed",
                    body: "Tessera saved this as \(saved) for these \(n) apps. Tile All Windows (⌃⌥T by default) brings it back any time.",
                    actions: [.done, .undoSplitChange]),
            ]
        case .tiledEvenly(let hasSplit):
            if hasSplit {
                return [CoachStep(
                    title: "Tiled evenly",
                    body: "Each window got \(CoachCopy.equalShare(n)). Your split for these apps is kept for the next Tile All Windows. Adjustments now aren't saved.",
                    actions: [.done])]
            }
            return [CoachStep(
                title: "Tiled evenly",
                body: "Each window got \(CoachCopy.equalShare(n)). Tile Evenly doesn't save what you change afterwards.",
                actions: [.done])]
        case .tilePartial(let moved, let total, let stuck):
            let who = stuck.isEmpty ? "Some windows" : CoachCopy.list(stuck)
            return [CoachStep(
                title: "Tiled \(moved) of \(total) windows",
                body: "\(who) wouldn't resize, so \(stuck.count == 1 ? "it" : "they") stayed where \(stuck.count == 1 ? "it was" : "they were"). The rest are in place, and Undo puts them back.",
                actions: [.undoMove, .done])]
        case .neighboursFollowed(let changed, let others):
            return [CoachStep(
                title: "Neighbours followed",
                body: "You resized \(changed), so \(CoachCopy.list(others)) moved to fill the space. You can turn this off in Settings › Splits.",
                actions: [.done, .undoMove, .openSplitsSettings])]
        case .gapFilled(let closed, let filled, let usedSplit):
            let gone = CoachCopy.list(closed)
            let body = usedSplit
                ? "\(gone) closed, so \(CoachCopy.list(apps)) went back to your split for these apps instead of leaving a gap."
                : "\(gone) closed, so \(CoachCopy.list(filled)) grew into the space. Tessera picks the window beside it you used last."
            return [CoachStep(
                title: "Space filled", body: body + " You can turn this off in Settings › Splits.",
                actions: [.done, .undoMove, .openSplitsSettings])]
        case .splitLearned:
            return [CoachStep(
                title: "Saved as your split",
                body: "Next time \(CoachCopy.list(apps)) are on \(event.displayName), Tile All Windows (⌃⌥T by default) puts them back like this.",
                actions: [.done, .forgetSplit])]
        case .splitNotLearned(let reason):
            return [CoachStep(
                title: "Not saved as a split",
                body: "\(reason). Tile All Windows (⌃⌥T by default) lines the windows up.",
                actions: [.tileAll, .done])]
        case .splitForgotten:
            return [forgotten(event)]
        }
    }

    /// After Forget This Split.
    public static func forgotten(_ event: HelpEvent) -> CoachStep {
        CoachStep(
            title: "Split forgotten",
            body: "Tessera forgot its split for \(CoachCopy.list(event.apps)) on \(event.displayName). The next Tile All Windows (⌃⌥T by default) gives each window an equal share.",
            actions: [.undoSplitChange, .done])
    }
}
