/// Why a newly opened window was not tiled in. The raw value is what the decision log prints.
public enum JoinSkip: String, Equatable, Sendable {
    /// The app has no new window on this display.
    case noNewWindow
    /// The new window is alone on the display: a lone window is never placed.
    case loneWindow
    /// A side-by-side group is here but one of its windows is missing (minimised, closed, another Space).
    case groupIncomplete
    /// No side-by-side group here, and the scope or the event does not allow starting one.
    case noGroup
    /// No group here and no learned split for exactly these apps (`rememberedSplits`).
    case noSplit
    /// A group starts only for an app just opened, not for one more window of a running app (⌘N, a background
    /// app's pop-up).
    case appAlreadyOpen
    /// Equal shares would spread several windows of one app.
    case sameApp
    /// More windows than the display has columns: a pile is not spread out.
    case tooMany
}

public enum JoinVerdict: Equatable, Sendable {
    /// Tile the windows found: in their learned split, or in equal shares when there is none.
    case tile(equalShares: Bool)
    /// No learned split, and the wait setting is on: tile only if the window is still open after it.
    case hold
    case skip(JoinSkip)
}

/// What one look at one display found. `watched` and `present` leave out the new windows themselves.
public struct JoinFacts: Equatable, Sendable {
    public var scope: SplitNewWindowScope
    /// A launch or a window-created event: the only events that may start a group on an untiled display.
    public var startsGroups: Bool
    /// Windows of the side-by-side group on this display, and how many of them are still visible.
    public var watched: Int
    public var present: Int
    /// Tileable windows on the display, the new ones included, and how many of them are new.
    public var found: Int
    public var joined: Int
    /// Different apps among `found`.
    public var apps: Int
    public var maxColumns: Int
    /// The app was just launched, or had no window on screen until now (reopened from the Dock) and is in front.
    public var freshApp: Bool
    /// The window returns to a group it left (relaunch after quit, restore after minimise).
    public var restored: Bool
    public var hasLearnedSplit: Bool
    /// The wait setting is on and this look comes before the wait.
    public var holds: Bool

    public init(scope: SplitNewWindowScope, startsGroups: Bool, watched: Int, present: Int, found: Int, joined: Int,
                apps: Int, maxColumns: Int, freshApp: Bool = true, restored: Bool = false, hasLearnedSplit: Bool = false,
                holds: Bool = false) {
        self.scope = scope; self.startsGroups = startsGroups; self.watched = watched; self.present = present
        self.found = found; self.joined = joined; self.apps = apps; self.maxColumns = maxColumns
        self.freshApp = freshApp
        self.restored = restored; self.hasLearnedSplit = hasLearnedSplit; self.holds = holds
    }
}

/// The rule for tiling a newly opened window in, kept free of windows and Accessibility so it can be table-tested.
public enum JoinDecision {
    public static func decide(_ f: JoinFacts) -> JoinVerdict {
        guard f.joined > 0 else { return .skip(.noNewWindow) }
        guard f.found > 1 || (f.restored && f.found == 1) else { return .skip(.loneWindow) }
        // The whole group is still here, so the new window joins it. A restored window rejoins what is left of it.
        let wasTiled = (f.present > 0 && (f.restored || f.present == f.watched))
            || (f.restored && f.found == 1 && f.joined == 1)
        if wasTiled {
            // A window coming back to what is left of its group, beside windows that were never in it, meets the same
            // limits as a group start: no spreading of one app's windows, no pile deeper than the columns.
            if f.restored, f.found - f.joined > f.present, !f.hasLearnedSplit {
                guard f.apps == f.found else { return .skip(.sameApp) }
                guard f.found <= f.maxColumns else { return .skip(.tooMany) }
            }
            return f.holds && !f.hasLearnedSplit ? .hold : .tile(equalShares: !f.hasLearnedSplit)
        }
        guard f.startsGroups, f.scope != .tiledDisplays else { return .skip(f.watched > 0 ? .groupIncomplete : .noGroup) }
        // Where no group is, only a fresh app starts one: one more window of a running app (⌘N, a pop-up from the
        // background) joins layouts but never begins one, learned split or not.
        if f.hasLearnedSplit { return f.freshApp ? .tile(equalShares: false) : .skip(f.watched > 0 ? .groupIncomplete : .appAlreadyOpen) }
        guard f.scope == .everyDisplay else { return .skip(.noSplit) }
        // Equal shares only start a group where none is: a group missing a member (minimised, hidden, another Space)
        // keeps that member's place.
        guard f.watched == 0 else { return .skip(.groupIncomplete) }
        guard f.freshApp else { return .skip(.appAlreadyOpen) }
        // One window each of different apps: never a browser's restored windows, never a pile deeper than the
        // display's columns.
        guard f.apps == f.found else { return .skip(.sameApp) }
        guard f.found <= f.maxColumns else { return .skip(.tooMany) }
        return f.holds ? .hold : .tile(equalShares: true)
    }
}
