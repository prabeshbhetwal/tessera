import Testing
@testable import TesseraCore

@Suite struct ColumnChangeTests {
    @Test func deltasClampExtremeAutomationValues() throws {
        let command = try CommandParser.parse(arguments: ["columns", "--delta", String(Int.max)])
        guard case .columns(let change, _) = command else { Issue.record("Expected columns command"); return }
        #expect(change.resolved(from: 5, within: 1...8) == 8)
        #expect(ColumnChange.delta(Int.min).resolved(from: 5, within: 1...8) == 1)
        #expect(ColumnChange.delta(1).resolved(from: Int.max, within: -16...16) == 16)
        #expect(ColumnChange.delta(-1).resolved(from: Int.min, within: -16...16) == -16)
    }

    @Test func ordinaryDeltasKeepExistingBehaviour() {
        #expect(ColumnChange.delta(1).resolved(from: 5, within: 1...8) == 6)
        #expect(ColumnChange.delta(-1).resolved(from: 5, within: 1...8) == 4)
        #expect(ColumnChange.delta(0).resolved(from: 5, within: 1...8) == 5)
        #expect(ColumnChange.delta(1).resolved(from: 8, within: 1...8) == 8)
        #expect(ColumnChange.delta(-1).resolved(from: 1, within: 1...8) == 1)
    }

    @Test func explicitCountsClampToDisplayRange() {
        #expect(ColumnChange.set(6).resolved(from: 5, within: 1...8) == 6)
        #expect(ColumnChange.set(Int.max).resolved(from: 5, within: 1...8) == 8)
        #expect(ColumnChange.set(Int.min).resolved(from: 5, within: 1...8) == 1)
    }
}
