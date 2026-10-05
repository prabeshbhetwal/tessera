import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

@Suite struct SplitMemoryTests {
    static func split(_ apps: [String], display: String = "d", at seconds: TimeInterval = 0) -> LearnedSplit {
        LearnedSplit(
            key: SplitKey(display: display, bundleIDs: apps),
            slots: apps.map { Slot(bundleID: $0, rect: UnitRect(x: 0, y: 0, width: 1, height: 1)) },
            updated: Date(timeIntervalSince1970: seconds)
        )
    }

    // MARK: SplitKey

    @Test func keyIgnoresAppOrder() {
        let a = SplitKey(display: "d", bundleIDs: ["b", "a", "a"])
        let b = SplitKey(display: "d", bundleIDs: ["a", "b", "a"])
        #expect(a == b)
        #expect(a.apps == ["a", "a", "b"])
    }

    @Test func keyDistinguishesCountAndDisplay() {
        #expect(SplitKey(display: "d", bundleIDs: ["a"]) != SplitKey(display: "d", bundleIDs: ["a", "a"]))
        #expect(SplitKey(display: "d1", bundleIDs: ["a"]) != SplitKey(display: "d2", bundleIDs: ["a"]))
    }

    @Test func keyMapsMissingBundleToPlaceholder() {
        #expect(SplitKey(display: "d", bundleIDs: [nil, "a"]).apps == ["?", "a"])
    }

    @Test func keyDecodesSorted() throws {
        let json = Data(#"{"display":"d","apps":["b","a","a"]}"#.utf8)
        let decoded = try JSONDecoder().decode(SplitKey.self, from: json)
        #expect(decoded.apps == ["a", "a", "b"])
        #expect(decoded == SplitKey(display: "d", bundleIDs: ["a", "b", "a"]))
    }

    // MARK: UnitRect

    @Test func unitRectRoundTrips() {
        let usable = CGRect(x: 100, y: 50, width: 1000, height: 500)
        let rect = CGRect(x: 350, y: 50, width: 500, height: 250)
        let unit = UnitRect(rect, in: usable)
        #expect(unit == UnitRect(x: 0.25, y: 0, width: 0.5, height: 0.5))
        #expect(unit.absolute(in: usable) == rect)
    }

    @Test func unitRectOfDegenerateFrameIsFiniteZero() {
        let unit = UnitRect(CGRect(x: 10, y: 10, width: 50, height: 50), in: .zero)
        #expect(unit == UnitRect(x: 0, y: 0, width: 0, height: 0))
    }

    // MARK: SplitMemory

    @Test func lookupFindsByKey() {
        let a = Self.split(["a"]), b = Self.split(["b"])
        #expect(SplitMemory.lookup(b.key, in: [a, b]) == b)
        #expect(SplitMemory.lookup(SplitKey(display: "d", bundleIDs: ["c"]), in: [a, b]) == nil)
    }

    @Test func upsertReplacesSameKeyAndMovesToNewest() {
        let k = Self.split(["k"], at: 1), other = Self.split(["o"], at: 2)
        let newer = Self.split(["k"], at: 3)
        let result = SplitMemory.upsert(newer, into: SplitMemory.upsert(other, into: SplitMemory.upsert(k, into: [])))
        #expect(result.filter { $0.key == k.key }.count == 1)
        #expect(result.last == newer)
        #expect(result.count == 2)
    }

    @Test func capDropsOldest() {
        var memory: [LearnedSplit] = []
        for i in 0...SplitMemory.capacity {
            memory = SplitMemory.upsert(Self.split(["app\(i)"], at: Double(i)), into: memory)
        }
        #expect(memory.count == SplitMemory.capacity)
        #expect(SplitMemory.lookup(SplitKey(display: "d", bundleIDs: ["app0"]), in: memory) == nil)
        #expect(SplitMemory.lookup(SplitKey(display: "d", bundleIDs: ["app1"]), in: memory) != nil)
    }

    @Test func forgetRemovesOnlyThatKey() {
        let a = Self.split(["a"]), b = Self.split(["b"])
        #expect(SplitMemory.forget(a.key, in: [a, b]) == [b])
        #expect(SplitMemory.forget(SplitKey(display: "d", bundleIDs: ["z"]), in: [a, b]) == [a, b])
    }

    // MARK: Codable

    @Test func splitRoundTripsThroughJSON() throws {
        let original = Self.split(["a", "b"], at: 100)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(LearnedSplit.self, from: data) == original)
    }
}
