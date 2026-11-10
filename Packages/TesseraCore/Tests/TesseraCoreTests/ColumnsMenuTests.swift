import Testing
@testable import TesseraCore

@Suite struct ColumnsMenuTests {
    @Test func listsOnlyTheDisplaysRangeAndTicksTheCurrentCount() {
        let entries = ColumnsMenu.entries(range: 2...4, current: 3)
        #expect(entries.map(\.title) == ["One More Column", "One Fewer Column", "2 Columns", "3 Columns", "4 Columns"])
        #expect(entries.filter(\.checked).map(\.change) == [.set(3)])
        #expect(entries.allSatisfy { $0.enabled })
    }

    @Test func greysTheStepThatWouldLeaveTheRange() {
        let atMax = ColumnsMenu.entries(range: 2...4, current: 4)
        #expect(atMax[0].enabled == false)
        #expect(atMax[1].enabled)
        let atMin = ColumnsMenu.entries(range: 1...4, current: 1)
        #expect(atMin[0].enabled)
        #expect(atMin[1].enabled == false)
        #expect(atMin[2].title == "1 Column")
    }
}
