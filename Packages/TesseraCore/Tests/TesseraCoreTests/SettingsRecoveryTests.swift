import Foundation
import Testing
@testable import TesseraCore

/// Load keeps everything it can: one bad value or item costs only itself, and a file it must not touch is left
/// alone with saving off for the session (audit: settings-file data-loss paths).
@Suite struct SettingsRecoveryTests {
    /// 1970-01-01 01:01:01 UTC, so copy and quarantine names are deterministic.
    private static let fixedNow = Date(timeIntervalSince1970: 3661)
    private static let quarantineName = "settings.corrupt-19700101-010101.json"
    private static let repairCopyName = "settings.pre-repair-19700101-010101.json"

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore(in dir: URL) -> SettingsStore {
        SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), now: { Self.fixedNow })
    }

    private func setWritable(_ dir: URL, _ writable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: dir.path)
    }

    private func customised() -> TesseraSettings {
        var s = TesseraSettings.defaults
        s.defaultGap = 12
        s.ring.deadZone = 14
        s.ring.wedges[0] = .topHalf
        s.themeName = "Glass"
        s.excludedBundleIDs = ["com.apple.Terminal"]
        s.displayOverrides["1-2-3"] = DisplayProfile(columns: 4, gap: 6, padding: 10, isUserOverride: true)
        var theme = Theme.glass
        theme.name = "Mine"
        s.customThemes = [theme]
        s.learnedSplits = [LearnedSplit(
            key: SplitKey(display: "1-2-3", bundleIDs: ["com.a", "com.b"]),
            slots: [Slot(bundleID: "com.a", rect: UnitRect(x: 0, y: 0, width: 0.6, height: 1)),
                    Slot(bundleID: "com.b", rect: UnitRect(x: 0.6, y: 0, width: 0.4, height: 1))],
            updated: Date(timeIntervalSince1970: 1000)
        )]
        return s
    }

    /// `customised()` as JSON, edited by `edit`, written as the settings file.
    private func writeEdited(_ dir: URL, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(customised())) as? [String: Any])
        edit(&object)
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: dir.appendingPathComponent("settings.json"))
        return bytes
    }

    // MARK: Newer schema

    /// After a rollback the newer file must still be there when the person upgrades again.
    @Test func newerSchemaIsLeftUntouchedAndNeverSavedOver() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        var newer = TesseraSettings.defaults
        newer.schemaVersion = 3
        let bytes = try JSONEncoder().encode(newer)
        try bytes.write(to: file)
        let store = makeStore(in: dir)

        let result = await store.load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == nil)
        #expect(result.saveRefusal == .newerSchema(3))
        await #expect(throws: SettingsStore.SaveRefusal.newerSchema(3)) { try await store.save(customised()) }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["settings.json"])
        #expect(result.notice?.message == "These settings were saved by a newer version of Tessera. "
            + "They are left untouched, and changes made now are not saved.")
    }

    // MARK: Read and move failures

    @Test func readErrorGivesDefaultsAndRefusesToSave() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A folder where the file should be: it exists, but reading it fails like an I/O error would.
        let file = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let store = makeStore(in: dir)

        let result = await store.load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == nil, "an unread file is never reported as set aside")
        #expect(result.saveRefusal == .unreadable)
        await #expect(throws: SettingsStore.SaveRefusal.unreadable) { try await store.save(.defaults) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["settings.json"])
    }

    @Test func failedMoveAsideIsNotReportedAsKeptAndIsNotSavedOver() async throws {
        let dir = try makeDirectory()
        defer { try? setWritable(dir, true); try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: file)
        try setWritable(dir, false)
        let store = makeStore(in: dir)

        let result = await store.load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == nil)
        #expect(result.saveRefusal == .notSetAside)
        await #expect(throws: SettingsStore.SaveRefusal.notSetAside) { try await store.save(.defaults) }
        #expect(try Data(contentsOf: file) == garbage)
        #expect(result.notice?.message.contains(file.path) == false)
    }

    @Test func repairWithoutACopyRefusesToSave() async throws {
        let dir = try makeDirectory()
        defer { try? setWritable(dir, true); try? FileManager.default.removeItem(at: dir) }
        let bytes = try writeEdited(dir) { $0["hudPosition"] = "sideways" }
        try setWritable(dir, false)
        let store = makeStore(in: dir)

        let result = await store.load()
        #expect(result.settings == customised(), "the repaired settings are still used this run")
        #expect(result.repairBackup == nil)
        #expect(result.saveRefusal == .noRepairBackup)
        await #expect(throws: SettingsStore.SaveRefusal.noRepairBackup) { try await store.save(result.settings) }
        #expect(try Data(contentsOf: dir.appendingPathComponent("settings.json")) == bytes)
    }

    // MARK: Repairs on load

    @Test func unknownEnumValuesFallBackToTheirDefaultsAndKeepTheRest() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = try writeEdited(dir) { object in
            object["hudPosition"] = "sideways"
            object["showHUD"] = "yes"
            var ring = object["ring"] as? [String: Any] ?? [:]
            ring["iconStyle"] = "emoji"
            object["ring"] = ring
        }

        let result = await makeStore(in: dir).load()
        #expect(result.settings == customised())
        #expect(result.recoveredFrom == nil)
        #expect(result.saveRefusal == nil)
        #expect(Set(result.repairs) == [
            "Reset the message position to its default.", "Reset the on-screen message setting to its default.",
            "Reset the ring icon style to its default.",
        ])
        #expect(result.repairBackup == dir.appendingPathComponent(Self.repairCopyName))
        #expect(try Data(contentsOf: dir.appendingPathComponent(Self.repairCopyName)) == bytes, "a copy, not a move")
        let rewritten = try JSONDecoder().decode(TesseraSettings.self, from: Data(contentsOf: dir.appendingPathComponent("settings.json")))
        #expect(rewritten == customised(), "the file now holds the repaired settings")
        #expect(result.notice?.title == "Some settings were repaired")
    }

    @Test func unknownCommandDropsOnlyThatHotkey() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writeEdited(dir) { object in
            var hotkeys = object["hotkeys"] as? [[String: Any]] ?? []
            hotkeys[0]["command"] = ["teleport": [String: Any]()]
            hotkeys[1]["enabled"] = nil
            object["hotkeys"] = hotkeys
        }

        let result = await makeStore(in: dir).load()
        #expect(result.settings.hotkeys == Array(HotkeyBinding.defaults.dropFirst()))
        #expect(result.repairs.contains("Removed the hotkey “cycle-left”, which this version can’t read."))
        #expect(result.repairs.contains("Reset the on/off switch in the hotkey “cycle-right” to its default."))
        #expect(result.settings.excludedBundleIDs == ["com.apple.Terminal"])
    }

    @Test func missingKeysInsideItemsTakeObviousDefaultsOrDropTheItem() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writeEdited(dir) { object in
            var cycles = object["cycles"] as? [[String: Any]] ?? []
            cycles[0]["display"] = nil
            object["cycles"] = cycles
            var overrides = object["displayOverrides"] as? [String: [String: Any]] ?? [:]
            overrides["1-2-3"]?["gap"] = nil
            overrides["4-5-6"] = ["gap": 3, "padding": 3, "isUserOverride": true]
            object["displayOverrides"] = overrides
            var splits = object["learnedSplits"] as? [[String: Any]] ?? []
            var slots = splits[0]["slots"] as? [[String: Any]] ?? []
            slots[0]["rect"] = nil
            splits[0]["slots"] = slots
            object["learnedSplits"] = splits
            var themes = object["customThemes"] as? [[String: Any]] ?? []
            var preview = themes[0]["preview"] as? [String: Any] ?? [:]
            preview["labelPosition"] = "floating"
            themes[0]["preview"] = preview
            object["customThemes"] = themes
        }

        let result = await makeStore(in: dir).load()
        var expected = customised()
        expected.displayOverrides["1-2-3"]?.gap = DisplayProfile(columns: 1).gap
        expected.learnedSplits = []
        expected.customThemes[0].preview.labelPosition = Theme.default.preview.labelPosition
        #expect(result.settings == expected)
        #expect(result.repairs.count == 5)
        #expect(result.repairs.contains { $0.hasPrefix("Reset the label position in the custom theme ") })
        #expect(result.repairs.contains { $0.hasPrefix("Reset the display choice in the cycle ") })
        #expect(!result.repairs.contains { $0.contains("labelPosition") || $0.contains(".display") })
        #expect(result.recoveredFrom == nil)
    }

    @Test func outOfRangeValuesAreClampedNotQuarantined() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writeEdited(dir) { object in
            object["defaultGap"] = 500
            var ring = object["ring"] as? [String: Any] ?? [:]
            ring["deadZone"] = 200
            object["ring"] = ring
        }

        let result = await makeStore(in: dir).load()
        var expected = customised()
        expected.defaultGap = SettingsValidation.maxSpacing
        expected.ring.deadZone = RingSettings.default.deadZone
        #expect(result.settings == expected)
        #expect(result.repairs == ["The default gap was 500 and is now 40."])
    }

    @Test func importRepairsTooButNeverTouchesTheSettingsFile() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var sevenWedges = customised()
        sevenWedges.ring.wedges.removeLast()
        let importFile = dir.appendingPathComponent("import.json")
        try JSONEncoder().encode(sevenWedges).write(to: importFile)

        let imported = try await makeStore(in: dir).importSettings(from: importFile)
        var expected = customised()
        expected.ring.wedges = RingSettings.default.wedges
        #expect(imported.settings == expected)
        #expect(imported.repairs.count == 1, "the import says what it fixed")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["import.json"])
    }

    @Test func fileWithoutAVersionIsStillSetAside() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data(#"{"defaultGap":3}"#.utf8)
        try bytes.write(to: dir.appendingPathComponent("settings.json"))

        let result = await makeStore(in: dir).load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == dir.appendingPathComponent(Self.quarantineName))
        #expect(try result.recoveredFrom.map { try Data(contentsOf: $0) } == bytes)
        #expect(result.saveRefusal == nil)
    }

    @Test func repairMessagesUsePlainNamesAndFallBackForUnknownPaths() {
        #expect(SettingNames.name(for: ["ring", "iconStyle"]) == "the ring icon style")
        #expect(SettingNames.name(for: ["preview", "labelPosition"], inItem: "customThemes") == "the label position")
        #expect(SettingNames.name(for: ["ring", "fillHex"], inItem: "customThemes") == "the ring colour")
        #expect(SettingNames.name(for: ["enabled"], inItem: "hotkeys") == "the on/off switch")
        #expect(SettingNames.name(for: ["ring", "somethingNew"]) == "a setting this version doesn’t recognise")
        #expect(SettingNames.name(for: ["colour"], inItem: "hotkeys") == SettingNames.unknown)
    }
}
