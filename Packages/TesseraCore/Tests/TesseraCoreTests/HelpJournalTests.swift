import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

@Suite struct HelpJournalTests {
    static func key(_ apps: [String] = ["a", "b"], display: String = "d") -> SplitKey {
        SplitKey(display: display, bundleIDs: apps)
    }

    static func event(
        _ kind: HelpEventKind = .tiled(usedSplit: false),
        source: CommandSource = .hotkey,
        key: SplitKey? = nil
    ) -> HelpEvent {
        HelpEvent(
            kind: kind,
            source: source,
            displayKey: "d",
            displayName: "CHG90",
            apps: ["Safari", "Notes"],
            frames: [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)],
            usable: CGRect(x: 0, y: 0, width: 200, height: 100),
            portrait: false,
            key: key,
            split: nil,
            previousSplit: nil
        )
    }

    @Test func capacityDropsOldest() {
        var journal = HelpJournal()
        let events = (0...HelpJournal.capacity).map { _ in Self.event() }
        events.forEach { journal.record($0) }
        #expect(journal.events.count == HelpJournal.capacity)
        #expect(!journal.events.contains { $0.id == events[0].id })
        #expect(journal.latest?.id == events.last?.id)
    }

    @Test func beforeAfterNavigate() {
        var journal = HelpJournal()
        let a = Self.event(), b = Self.event(), c = Self.event()
        [a, b, c].forEach { journal.record($0) }
        #expect(journal.event(before: c.id)?.id == b.id)
        #expect(journal.event(before: b.id)?.id == a.id)
        #expect(journal.event(before: a.id) == nil)
        #expect(journal.event(after: a.id)?.id == b.id)
        #expect(journal.event(after: b.id)?.id == c.id)
        #expect(journal.event(after: c.id) == nil)
        #expect(journal.event(before: UUID()) == nil)
        #expect(journal.event(after: UUID()) == nil)
    }

    @Test func lastTileSkipsOtherKeysAndKinds() {
        let k = Self.key(), other = Self.key(["x", "y"])
        var journal = HelpJournal()
        let target = Self.event(.tiled(usedSplit: false), key: k)
        let otherKey = Self.event(.tiled(usedSplit: true), key: other)
        let evenly = Self.event(.tiledEvenly(hasSplit: true), key: k)
        let partial = Self.event(.tilePartial(moved: 1, total: 2, stuck: ["Notes"]), key: k)
        let current = Self.event(.tiled(usedSplit: true), key: k)
        [target, otherKey, evenly, partial, current].forEach { journal.record($0) }
        #expect(journal.lastTile(for: k, before: current.id)?.id == target.id)
        #expect(journal.lastTile(for: k, before: target.id) == nil)
        #expect(journal.lastTile(for: other, before: current.id)?.id == otherKey.id)
        #expect(journal.lastTile(for: k, before: UUID()) == nil)
    }

    @Test func momentMapping() {
        let cases: [(HelpEventKind, CoachMoment)] = [
            (.tiled(usedSplit: true), .tiledWithSplit),
            (.tiled(usedSplit: false), .tiledEqual),
            (.tiledEvenly(hasSplit: true), .tiledEvenly),
            (.tiledEvenly(hasSplit: false), .tiledEvenly),
            (.tilePartial(moved: 1, total: 2, stuck: ["Notes"]), .tilePartial),
            (.neighboursFollowed(changed: "Safari", followers: ["Notes"]), .neighboursFollowed),
            (.splitLearned, .splitLearned),
            (.splitNotLearned(reason: "overlap"), .splitNotLearned),
            (.splitForgotten, .splitForgotten),
        ]
        for (kind, moment) in cases {
            #expect(Self.event(kind).moment == moment)
        }
        #expect(Set(cases.map(\.1)) == Set(CoachMoment.allCases))
    }

    @Test func nonEvents() {
        #expect(Self.event(.tilePartial(moved: 0, total: 2, stuck: [])).isNonEvent)
        #expect(Self.event(.splitNotLearned(reason: "x")).isNonEvent)
        let others: [HelpEventKind] = [
            .tiled(usedSplit: true), .tiled(usedSplit: false), .tiledEvenly(hasSplit: false),
            .neighboursFollowed(changed: "a", followers: []), .splitLearned, .splitForgotten,
        ]
        for kind in others { #expect(!Self.event(kind).isNonEvent) }
    }

    @Test func stillMatches() {
        let k = Self.key()
        let event = Self.event(key: k)
        #expect(event.stillMatches(k))
        #expect(event.stillMatches(Self.key(["b", "a"])))
        #expect(!event.stillMatches(nil))
        #expect(!event.stillMatches(Self.key(["x"])))
        #expect(!Self.event(key: nil).stillMatches(nil))
    }

    @Test func interactiveSources() {
        for s: CommandSource in [.ring, .hotkey, .menu, .hand] { #expect(s.isInteractive) }
        for s: CommandSource in [.coach, .automation] { #expect(!s.isInteractive) }
    }
}
