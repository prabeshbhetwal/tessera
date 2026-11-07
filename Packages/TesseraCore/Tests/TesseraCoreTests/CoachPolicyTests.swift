import Foundation
import Testing
@testable import TesseraCore

@Suite struct CoachPolicyTests {
    private let noon = Date(timeIntervalSince1970: 1_728_043_200)
    private var nextNoon: Date { noon.addingTimeInterval(86_400) }

    private func event(_ kind: HelpEventKind = .tiled(usedSplit: true), source: CommandSource = .hotkey) -> HelpEvent {
        HelpEvent(kind: kind, source: source, date: noon, displayKey: "d", displayName: "this display",
                  apps: [], frames: [], usable: .zero, portrait: false, key: nil, split: nil, previousSplit: nil)
    }

    private func ctx(ring: Bool = false, mouse: Bool = false, typing: Double = 10,
                     showing: Bool = false, now: Date? = nil) -> CoachContext {
        CoachContext(ringOpen: ring, mouseDown: mouse, secondsSinceTyping: typing, coachShowing: showing, now: now ?? noon)
    }

    private func help(autoShow: Bool = true, seen: [CoachMoment] = []) -> HelpSettings {
        var h = HelpSettings()
        h.autoShow = autoShow
        h.seenMoments = Set(seen.map(\.rawValue))
        return h
    }

    private func show(_ e: HelpEvent, _ h: HelpSettings? = nil, _ c: CoachContext? = nil, prev: HelpEvent? = nil,
                      policy: inout CoachPolicy) -> CoachPresentation? {
        policy.presentation(for: e, help: h ?? help(), previousTile: prev, context: c ?? ctx())
    }

    @Test func automationNeverShows() {
        var p = CoachPolicy()
        #expect(show(event(source: .automation), policy: &p) == nil)
    }

    @Test func coachSourceNeverShows() {
        var p = CoachPolicy()
        #expect(show(event(source: .coach), policy: &p) == nil)
    }

    @Test func autoShowOffNeverShows() {
        var p = CoachPolicy()
        #expect(show(event(), help(autoShow: false), policy: &p) == nil)
    }

    @Test func ringOpenSuppresses() {
        var p = CoachPolicy()
        #expect(show(event(), nil, ctx(ring: true), policy: &p) == nil)
    }

    @Test func mouseDownSuppresses() {
        var p = CoachPolicy()
        #expect(show(event(), nil, ctx(mouse: true), policy: &p) == nil)
    }

    @Test func coachShowingSuppresses() {
        var p = CoachPolicy()
        #expect(show(event(), nil, ctx(showing: true), policy: &p) == nil)
    }

    @Test func handTypingSuppresses() {
        var p = CoachPolicy()
        #expect(show(event(source: .hand), nil, ctx(typing: 1.9), policy: &p) == nil)
    }

    @Test func hotkeyTypingDoesNot() {
        var p = CoachPolicy()
        #expect(show(event(source: .hotkey), nil, ctx(typing: 0.1), policy: &p) == .full)
    }

    @Test func firstTimeFull() {
        var p = CoachPolicy()
        #expect(show(event(), policy: &p) == .full)
    }

    @Test func firstTimeNonEventLight() {
        var p = CoachPolicy()
        #expect(show(event(.tilePartial(moved: 1, total: 2, stuck: ["A"])), policy: &p) == .light)
    }

    @Test func seenGivesNil() {
        var p = CoachPolicy()
        #expect(show(event(), help(seen: [.tiledWithSplit]), policy: &p) == nil)
    }

    @Test func partialAlwaysLight() {
        var p = CoachPolicy()
        let e = event(.tilePartial(moved: 1, total: 2, stuck: ["A"]))
        #expect(show(e, help(seen: [.tilePartial]), policy: &p) == .light)
    }

    @Test func notLearnedOncePerDay() {
        var p = CoachPolicy()
        let e = event(.splitNotLearned(reason: "too narrow"))
        let h = help(seen: [.splitNotLearned])
        #expect(show(e, h, ctx(now: noon), policy: &p) == .light)
        #expect(show(e, h, ctx(now: noon.addingTimeInterval(60)), policy: &p) == nil)
        #expect(show(e, h, ctx(now: nextNoon), policy: &p) == .light)
    }

    @Test func notLearnedFirstTimeCountsForTheDay() {
        var p = CoachPolicy()
        let e = event(.splitNotLearned(reason: "too narrow"))
        #expect(show(e, nil, ctx(now: noon), policy: &p) == .light)
        #expect(show(e, help(seen: [.splitNotLearned]), ctx(now: noon.addingTimeInterval(60)), policy: &p) == nil)
    }

    @Test func usedSplitFlipIsLight() {
        var p = CoachPolicy()
        let h = help(seen: [.tiledWithSplit, .tiledEqual])
        let prev = event(.tiled(usedSplit: false))
        #expect(show(event(.tiled(usedSplit: true)), h, prev: prev, policy: &p) == .light)
        #expect(show(event(.tiled(usedSplit: true)), h, prev: event(.tiled(usedSplit: true)), policy: &p) == nil)
        #expect(show(event(.tiled(usedSplit: true)), h, prev: nil, policy: &p) == nil)
    }
}
