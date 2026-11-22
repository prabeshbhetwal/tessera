import Testing
@testable import TesseraCore

/// The cold-start table: what opening windows on a display does under each scope.
@Suite struct JoinDecisionTests {
    private func facts(_ scope: SplitNewWindowScope, startsGroups: Bool = true, watched: Int = 0, present: Int = 0,
                       found: Int, joined: Int = 1, apps: Int? = nil, maxColumns: Int = 4, fresh: Bool = true,
                       restored: Bool = false, learned: Bool = false, holds: Bool = false) -> JoinFacts {
        JoinFacts(scope: scope, startsGroups: startsGroups, watched: watched, present: present, found: found,
                  joined: joined, apps: apps ?? found, maxColumns: maxColumns, freshApp: fresh, restored: restored,
                  hasLearnedSplit: learned, holds: holds)
    }

    @Test func aLoneWindowIsNeverPlaced() {
        for scope in SplitNewWindowScope.allCases {
            #expect(JoinDecision.decide(facts(scope, found: 1)) == .skip(.loneWindow))
        }
    }

    @Test func emptyDisplayThenSecondApp() {
        #expect(JoinDecision.decide(facts(.tiledDisplays, found: 2)) == .skip(.noGroup))
        #expect(JoinDecision.decide(facts(.rememberedSplits, found: 2)) == .skip(.noSplit))
        #expect(JoinDecision.decide(facts(.rememberedSplits, found: 2, learned: true)) == .tile(equalShares: false))
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 2)) == .tile(equalShares: true))
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 3, learned: true)) == .tile(equalShares: false))
    }

    @Test func onlyALaunchOrNewWindowStartsAGroup() {
        #expect(JoinDecision.decide(facts(.everyDisplay, startsGroups: false, found: 2)) == .skip(.noGroup))
        #expect(JoinDecision.decide(facts(.everyDisplay, startsGroups: false, found: 2, learned: true)) == .skip(.noGroup))
    }

    @Test func equalSharesNeverSpreadOneAppsWindowsOrAPile() {
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 3, apps: 2)) == .skip(.sameApp))
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 5, maxColumns: 4)) == .skip(.tooMany))
        // A learned split for exactly these windows still applies.
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 3, apps: 2, learned: true)) == .tile(equalShares: false))
    }

    @Test func aNewWindowJoinsAWholeGroupUnderEveryScope() {
        for scope in SplitNewWindowScope.allCases {
            #expect(JoinDecision.decide(facts(scope, startsGroups: false, watched: 2, present: 2, found: 3))
                    == .tile(equalShares: true))
            #expect(JoinDecision.decide(facts(scope, watched: 2, present: 2, found: 3, learned: true))
                    == .tile(equalShares: false))
        }
    }

    @Test func aGroupMissingAMemberIsNotJoinedByAnActivation() {
        #expect(JoinDecision.decide(facts(.tiledDisplays, watched: 2, present: 1, found: 2)) == .skip(.groupIncomplete))
        #expect(JoinDecision.decide(facts(.everyDisplay, startsGroups: false, watched: 2, present: 1, found: 2))
                == .skip(.groupIncomplete))
        // The missing member keeps its place: equal shares never start over a group, a learned split still applies.
        #expect(JoinDecision.decide(facts(.everyDisplay, watched: 2, present: 1, found: 2)) == .skip(.groupIncomplete))
        #expect(JoinDecision.decide(facts(.everyDisplay, watched: 2, present: 1, found: 2, learned: true))
                == .tile(equalShares: false))
    }

    /// ⌘N, a Finder folder, a background app's pop-up: one more window of a running app starts no group.
    @Test func onlyAFreshAppStartsEqualShares() {
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 2, fresh: false)) == .skip(.appAlreadyOpen))
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 2, fresh: false, learned: true)) == .skip(.appAlreadyOpen))
        #expect(JoinDecision.decide(facts(.rememberedSplits, found: 2, fresh: false, learned: true)) == .skip(.appAlreadyOpen))
        // One more window beside a group missing a member keeps that member's place, split or not.
        #expect(JoinDecision.decide(facts(.rememberedSplits, watched: 2, present: 1, found: 2, fresh: false, learned: true))
                == .skip(.groupIncomplete))
    }

    /// A relaunched app rejoins what is left of its group, but not by spreading every unrelated window on the display.
    @Test func aRestoredWindowMeetsTheStartLimitsBesideStrangers() {
        // Peer + newcomer + three windows of two other apps, one of them twice.
        #expect(JoinDecision.decide(facts(.tiledDisplays, startsGroups: false, watched: 1, present: 1, found: 5, apps: 4,
                                          restored: true)) == .skip(.sameApp))
        #expect(JoinDecision.decide(facts(.tiledDisplays, startsGroups: false, watched: 1, present: 1, found: 5,
                                          maxColumns: 4, restored: true)) == .skip(.tooMany))
        #expect(JoinDecision.decide(facts(.tiledDisplays, startsGroups: false, watched: 1, present: 1, found: 3,
                                          restored: true)) == .tile(equalShares: true))
        #expect(JoinDecision.decide(facts(.tiledDisplays, startsGroups: false, watched: 1, present: 1, found: 5, apps: 4,
                                          restored: true, learned: true)) == .tile(equalShares: false))
        #expect(JoinDecision.decide(facts(.everyDisplay, watched: 2, present: 2, found: 3, fresh: false))
                == .tile(equalShares: true))
    }

    @Test func aRestoredWindowRejoinsWhatIsLeft() {
        #expect(JoinDecision.decide(facts(.tiledDisplays, startsGroups: false, watched: 2, present: 1, found: 2, restored: true))
                == .tile(equalShares: true))
        #expect(JoinDecision.decide(facts(.tiledDisplays, startsGroups: false, found: 1, restored: true))
                == .tile(equalShares: true))
    }

    @Test func theWaitHoldsEqualSharesButNotALearnedSplit() {
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 2, holds: true)) == .hold)
        #expect(JoinDecision.decide(facts(.tiledDisplays, watched: 2, present: 2, found: 3, holds: true)) == .hold)
        #expect(JoinDecision.decide(facts(.everyDisplay, found: 2, learned: true, holds: true)) == .tile(equalShares: false))
    }

    @Test func noNewWindowMeansNothingToDo() {
        #expect(JoinDecision.decide(facts(.everyDisplay, watched: 2, present: 2, found: 2, joined: 0)) == .skip(.noNewWindow))
    }
}
