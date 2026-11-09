import Foundation
import Testing
@testable import TesseraCore

@Suite struct SettingsSearchTests {
    private func top(_ query: String) -> String? { SettingsSearch.results(for: query).first?.id }

    @Test(arguments: [
        ("remove the gap between tiled apps", "displays/Gap"),
        ("no space between windows", "displays/Gap"),
        ("spacing", "displays/Gap"),
        ("gutter", "displays/Gap"),
        ("gpa", "displays/Gap"),
        ("paddng", "displays/Padding"),
        ("pad", "displays/Padding"),
        ("margin around the screen edge", "displays/Padding"),
        ("open when my mac starts", "general/Launch at login"),
        ("launch on startup", "general/Launch at login"),
        ("dark mode", "general/Appearance"),
        ("hide menu bar icon", "general/Show the menu bar icon"),
        ("beta", "updates/Include beta versions"),
        ("auto update", "updates/Check for updates automatically"),
        ("how fast windows move", "motion/Speed"),
        ("animation speed", "motion/Speed"),
        ("turn off tessera in one app", "excludedApps/Apps"),
        ("keyboard shortcuts", "shortcuts/Add Hotkey"),
        ("turn global hotkeys off", "shortcuts/Use global hotkeys"),
        ("ring size", "ring/Radius"),
        ("colour of the ring", "overlay/Ring"),
        ("color of the ring", "overlay/Ring"),
        ("preview transparency", "overlay/Fill opacity"),
        ("rounded corners", "overlay/Corner radius"),
        ("how many columns", "displays/Columns"),
        ("trigger keys", "ring/Chord"),
        ("invisible ring", "overlay/Show the ring"),
        ("gap on other monitors", "displays/New displays gap"),
        ("smart search", "general/Apple Intelligence search"),
        ("export settings", "general/Advanced"),
        ("forget learned splits", "splits/Forget All…"),
    ])
    func findsTheSettingMeant(query: String, expected: String) {
        #expect(top(query) == expected, "\(query) → \(SettingsSearch.results(for: query).prefix(3).map(\.id))")
    }

    @Test func emptyAndNonsenseFindNothing() {
        #expect(SettingsSearch.results(for: "").isEmpty)
        #expect(SettingsSearch.results(for: "   ").isEmpty)
        #expect(SettingsSearch.results(for: "xqzv").isEmpty)
        #expect(SettingsSearch.results(for: "banana smoothie").isEmpty)
    }

    @Test func resetFindsEveryPanesRestoreDefaults() {
        let panes = Set(SettingsSearch.results(for: "reset", limit: 20).filter { $0.title == "Restore Defaults" }.map(\.pane))
        #expect(panes.count >= 8)
    }

    @Test func ignoresCaseAccentsAndPunctuation() {
        #expect(top("GAP!") == "displays/Gap")
        #expect(top("Thíckness") == "ring/Thickness")
    }

    @Test func distanceCountsAdjacentSwapsAsOne() {
        #expect(SettingsSearch.distance("gap", "gpa") == 1)
        #expect(SettingsSearch.distance("padding", "paddng") == 1)
        #expect(SettingsSearch.distance("", "abc") == 3)
    }

    @Test func entryIDsAreUnique() {
        let ids = SettingsCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

/// Every anchored catalog entry must be tagged in the app, or clicking its result scrolls nowhere.
@Suite struct SettingsCatalogTests {
    private static let uiSource: String = {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tessera/UI")
        let files = (try? FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }()

    @Test func uiSourcesAreReadable() {
        #expect(Self.uiSource.contains("struct SettingsView"))
    }

    @Test(arguments: SettingsCatalog.entries.compactMap(\.anchor))
    func anchorIsTaggedInTheApp(anchor: String) throws {
        let literal = NSRegularExpression.escapedPattern(for: "\"\(anchor)\"")
        let tagged = try Regex("settingAnchor\\(\(literal)\\)|(SliderRow|StepperRow)\\(\\s*title:[^,]*\(literal)|anchor:[^,)]*\(literal)")
        let found = Self.uiSource.contains(tagged)
        #expect(found, "Tag the row with .settingAnchor(\"\(anchor)\")")
    }
}
