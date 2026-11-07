import CoreGraphics
import Foundation

/// Where a command came from. Only interactive sources show the coach on their own.
public enum CommandSource: String, Codable, Sendable {
    case ring, hotkey, menu, hand, coach, automation

    public var isInteractive: Bool {
        switch self {
        case .ring, .hotkey, .menu, .hand: true
        case .coach, .automation: false
        }
    }
}

public enum HelpEventKind: Equatable, Sendable {
    case tiled(usedSplit: Bool)
    case tiledEvenly(hasSplit: Bool)
    case tilePartial(moved: Int, total: Int, stuck: [String])
    case neighboursFollowed(changed: String, followers: [String])
    case splitLearned
    case splitNotLearned(reason: String)
    case splitForgotten
}

public enum CoachMoment: String, CaseIterable, Sendable {
    case tiledWithSplit, tiledEqual, tiledEvenly, tilePartial, neighboursFollowed, splitLearned, splitNotLearned, splitForgotten
}

/// One thing the coach can explain: what happened, to which apps, and where they sit.
public struct HelpEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var kind: HelpEventKind
    public var source: CommandSource
    public var date: Date
    /// `DisplayID.storageKey`.
    public var displayKey: String
    /// "CHG90", or "this display".
    public var displayName: String
    /// App names in on-screen order (left to right; top to bottom on portrait).
    public var apps: [String]
    /// AppKit global frames, same order as `apps`.
    public var frames: [CGRect]
    /// `GridGeometry.usableFrame` of the display.
    public var usable: CGRect
    public var portrait: Bool
    public var key: SplitKey?
    /// The split in effect after the event (used or just learned).
    public var split: LearnedSplit?
    /// For `splitLearned` / `splitForgotten`: what Undo restores.
    public var previousSplit: LearnedSplit?
    /// The window undo history's marker right after the event's moves; the coach's Undo runs only while it still holds.
    public var undoMarker: Int?

    public init(
        id: UUID = UUID(),
        kind: HelpEventKind,
        source: CommandSource,
        date: Date = Date(),
        displayKey: String,
        displayName: String,
        apps: [String],
        frames: [CGRect],
        usable: CGRect,
        portrait: Bool,
        key: SplitKey?,
        split: LearnedSplit?,
        previousSplit: LearnedSplit?,
        undoMarker: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.date = date
        self.displayKey = displayKey
        self.displayName = displayName
        self.apps = apps
        self.frames = frames
        self.usable = usable
        self.portrait = portrait
        self.key = key
        self.split = split
        self.previousSplit = previousSplit
        self.undoMarker = undoMarker
    }

    public var moment: CoachMoment {
        switch kind {
        case .tiled(let usedSplit): usedSplit ? .tiledWithSplit : .tiledEqual
        case .tiledEvenly: .tiledEvenly
        case .tilePartial: .tilePartial
        case .neighboursFollowed: .neighboursFollowed
        case .splitLearned: .splitLearned
        case .splitNotLearned: .splitNotLearned
        case .splitForgotten: .splitForgotten
        }
    }

    /// Something that did not happen (a partial tile, a split not learned) rather than a change.
    public var isNonEvent: Bool {
        switch kind {
        case .tilePartial, .splitNotLearned: true
        default: false
        }
    }

    public func stillMatches(_ current: SplitKey?) -> Bool {
        key != nil && key == current
    }
}
