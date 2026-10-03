import Foundation
import Testing

@testable import TesseraCore

private let newKeys = ["hotkeys", "cycles", "ringKeyNavigation", "announceSelection"]

/// A settings file exactly as the M1 build wrote it: schema 1 and none of the M2 keys.
private func v1Data(from s: TesseraSettings, pretty: Bool = true) throws -> Data {
    let encoded = try JSONEncoder().encode(s)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    for key in newKeys { object[key] = nil }
    object["schemaVersion"] = 1
    return try JSONSerialization.data(withJSONObject: object, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])
}

private func userSettings() -> TesseraSettings {
    var s = TesseraSettings.defaults
    s.defaultGap = 12
    s.ring.deadZone = 14
    s.themeName = "Glass"
    s.excludedBundleIDs = ["com.apple.Terminal"]
    s.displayOverrides["1-2-3"] = DisplayProfile(columns: 4, gap: 6, padding: 10, isUserOverride: true)
    s.displayOverrides["uuid:abc"] = DisplayProfile(columns: 6, gap: 8, padding: 8, isUserOverride: true)
    return s
}

private func makeDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tessera-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite struct SettingsMigrationTests {
    // MARK: migrate()

    @Test func v1GainsTheNewKeysWithDefaultsAndSchema2() throws {
        let v1 = try v1Data(from: userSettings())
        let result = try SettingsMigration.migrate(v1)
        #expect(result.migratedFrom == 1)

        let migrated = try JSONDecoder().decode(TesseraSettings.self, from: result.data)
        #expect(migrated.schemaVersion == 2)
        #expect(migrated.hotkeys == HotkeyBinding.defaults)
        #expect(migrated.cycles == Cycle.defaults)
        #expect(migrated.ringKeyNavigation == true)
        #expect(migrated.announceSelection == true)
    }

    // Review Focus 5
    @Test func v1KeepsEveryExistingValueIncludingDisplayOverrides() throws {
        let original = userSettings()
        let result = try SettingsMigration.migrate(try v1Data(from: original))
        let migrated = try JSONDecoder().decode(TesseraSettings.self, from: result.data)

        var expected = original
        expected.schemaVersion = 2
        #expect(migrated == expected)
        #expect(migrated.displayOverrides["1-2-3"] == DisplayProfile(columns: 4, gap: 6, padding: 10, isUserOverride: true))
        #expect(migrated.displayOverrides["uuid:abc"]?.columns == 6)
    }

    @Test func migratedDataPassesValidation() throws {
        let result = try SettingsMigration.migrate(try v1Data(from: userSettings()))
        let migrated = try JSONDecoder().decode(TesseraSettings.self, from: result.data)
        try SettingsValidation.validate(migrated)
    }

    @Test func v1WithSomeNewKeysAlreadyPresentKeepsThem() throws {
        var s = userSettings()
        s.ringKeyNavigation = false
        s.cycles = [Cycle(name: "mine", steps: [.action(.maximize)])]
        let encoded = try JSONEncoder().encode(s)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["hotkeys"] = nil
        object["announceSelection"] = nil
        object["schemaVersion"] = 1
        let partial = try JSONSerialization.data(withJSONObject: object)

        let result = try SettingsMigration.migrate(partial)
        let migrated = try JSONDecoder().decode(TesseraSettings.self, from: result.data)
        #expect(migrated.ringKeyNavigation == false)
        #expect(migrated.cycles == s.cycles)
        #expect(migrated.hotkeys == HotkeyBinding.defaults)
        #expect(migrated.announceSelection == true)
    }

    @Test func v2AndNewerAreReturnedUntouched() throws {
        let v2 = try JSONEncoder().encode(TesseraSettings.defaults)
        let same = try SettingsMigration.migrate(v2)
        #expect(same.migratedFrom == nil)
        #expect(same.data == v2)

        var newer = TesseraSettings.defaults
        newer.schemaVersion = 3
        let v3 = try JSONEncoder().encode(newer)
        let untouched = try SettingsMigration.migrate(v3)
        #expect(untouched.migratedFrom == nil)
        #expect(untouched.data == v3)
    }

    @Test func migrationIsIdempotent() throws {
        let once = try SettingsMigration.migrate(try v1Data(from: userSettings()))
        let twice = try SettingsMigration.migrate(once.data)
        #expect(twice.migratedFrom == nil)
        #expect(twice.data == once.data)
    }

    @Test func unrecognisedInputIsLeftForTheDecoderToReject() throws {
        let noVersion = Data(#"{"trigger":{}}"#.utf8)
        let r = try SettingsMigration.migrate(noVersion)
        #expect(r.migratedFrom == nil && r.data == noVersion)
    }

    /// A supported file missing keys (hand-edited, or written before a setting existed) gets those
    /// keys from the defaults, nested ones included, and keeps everything else. No version bump, so
    /// `migratedFrom` stays nil and no backup is made.
    @Test func missingKeysAreFilledFromDefaultsRecursively() throws {
        let s = userSettings()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        object["preview"] = nil
        object["snapDuration"] = nil
        var ring = try #require(object["ring"] as? [String: Any])
        ring["flickDistance"] = nil
        object["ring"] = ring

        let r = try SettingsMigration.migrate(try JSONSerialization.data(withJSONObject: object))
        #expect(r.migratedFrom == nil)
        let migrated = try JSONDecoder().decode(TesseraSettings.self, from: r.data)
        var expected = s
        expected.preview = .default
        expected.snapDuration = 0
        expected.ring.flickDistance = RingSettings.default.flickDistance
        #expect(migrated == expected)
        #expect(migrated.ring.deadZone == 14, "sibling keys inside a filled object are kept")
        #expect(migrated.displayOverrides.count == 2, "user-keyed maps are never touched")
    }

    /// A custom theme saved before a theme field existed gets that field from the Default theme and keeps
    /// its own name and colours. Without this the whole file would fail to decode and be set aside.
    @Test func customThemesGainMissingKeys() throws {
        var s = TesseraSettings.defaults
        var mine = Theme.glass
        mine.name = "Mine"
        mine.ring.fillHex = "#123456"
        mine.accentHex = "#FF3B30"
        s.customThemes = [mine]
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        var themes = try #require(object["customThemes"] as? [[String: Any]])
        themes[0]["previewHex"] = nil
        var ring = try #require(themes[0]["ring"] as? [String: Any])
        ring["gridHex"] = nil
        themes[0]["ring"] = ring
        var preview = try #require(themes[0]["preview"] as? [String: Any])
        preview["showOutline"] = nil
        themes[0]["preview"] = preview
        object["customThemes"] = themes

        let decoded = try SettingsStore.decode(JSONSerialization.data(withJSONObject: object)).settings
        let theme = try #require(decoded.customThemes.first)
        #expect(theme.name == "Mine" && theme.ring.fillHex == "#123456")
        #expect(theme.previewHex == "#FF3B30", "an old theme's preview keeps its accent colour")
        #expect(theme.ring.gridHex == Theme.default.ring.gridHex)
        #expect(theme.preview.showOutline == true)
    }

    /// A file from before the menu bar, message and icon options loads with their defaults and keeps the rest.
    @Test func newCustomisationOptionsGetDefaults() throws {
        var s = userSettings()
        s.menuBarItems.undo = false
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        for key in ["menuBarIcon", "hudPosition", "hudSeconds", "appearance"] { object[key] = nil }
        var items = try #require(object["menuBarItems"] as? [String: Any])
        items["snapSubmenu"] = nil
        object["menuBarItems"] = items
        var ring = try #require(object["ring"] as? [String: Any])
        ring["iconStyle"] = nil
        object["ring"] = ring

        let decoded = try SettingsStore.decode(JSONSerialization.data(withJSONObject: object)).settings
        #expect(decoded.menuBarIcon == .grid && decoded.hudPosition == .bottom && decoded.appearance == .system)
        #expect(decoded.hudSeconds == TesseraSettings.defaults.hudSeconds)
        #expect(decoded.ring.iconStyle == .layouts)
        #expect(decoded.menuBarItems.snapSubmenu == true, "a missing item gets its default")
        #expect(decoded.menuBarItems.undo == false, "an item the user turned off stays off")
        #expect(decoded.defaultGap == 12)
    }

    @Test func filledFileStillValidates() throws {
        let sparse = Data(#"{"schemaVersion":2,"defaultGap":3}"#.utf8)
        let decoded = try SettingsStore.decode(sparse)
        #expect(decoded.migratedFrom == nil)
        var expected = TesseraSettings.defaults
        expected.defaultGap = 3
        #expect(decoded.settings == expected)
    }

    @Test func notJSONThrows() {
        #expect(throws: (any Error).self) { try SettingsMigration.migrate(Data("{ not json".utf8)) }
        #expect(throws: (any Error).self) { try SettingsMigration.migrate(Data("[1,2]".utf8)) }
        #expect(throws: (any Error).self) { try SettingsMigration.migrate(Data()) }
    }

    // MARK: SettingsStore.load() / importSettings()

    private func makeStore(_ dir: URL) -> SettingsStore {
        SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), now: { Date(timeIntervalSince1970: 3661) })
    }

    // Review Focus 5
    @Test func loadMigratesV1WritesBackupAndSavesV2() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let backup = dir.appendingPathComponent("settings.v1-backup.json")
        let v1 = try v1Data(from: userSettings())
        try v1.write(to: file)

        let result = await makeStore(dir).load()

        var expected = userSettings()
        expected.schemaVersion = 2
        #expect(result.settings == expected)
        #expect(result.recoveredFrom == nil)
        #expect(result.settings.displayOverrides["1-2-3"]?.columns == 4)
        #expect(try Data(contentsOf: backup) == v1, "backup must hold the original v1 bytes")

        let onDisk = try JSONDecoder().decode(TesseraSettings.self, from: Data(contentsOf: file))
        #expect(onDisk == expected, "settings.json must now be v2")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            == ["settings.json", "settings.v1-backup.json"])
    }

    @Test func secondLoadDoesNotMigrateOrBackUpAgain() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try v1Data(from: userSettings()).write(to: dir.appendingPathComponent("settings.json"))
        let store = makeStore(dir)

        let first = await store.load()
        let second = await store.load()
        #expect(first.settings == second.settings)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            == ["settings.json", "settings.v1-backup.json"])
    }

    @Test func existingBackupIsNeverOverwritten() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backup = dir.appendingPathComponent("settings.v1-backup.json")
        let precious = Data("older v1 backup".utf8)
        try precious.write(to: backup)
        let v1 = try v1Data(from: userSettings())
        try v1.write(to: dir.appendingPathComponent("settings.json"))

        let result = await makeStore(dir).load()
        #expect(result.settings.schemaVersion == 2)
        #expect(try Data(contentsOf: backup) == precious)
        // The v1 bytes being replaced are still kept, under another name.
        let others = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("settings.v1-backup") && $0 != "settings.v1-backup.json" }
        #expect(others.count == 1)
        #expect(try Data(contentsOf: dir.appendingPathComponent(others[0])) == v1)
    }

    @Test func v2FileIsLoadedWithoutBackup() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(dir)
        try await store.save(userSettings())

        let result = await store.load()
        #expect(result.settings.schemaVersion == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["settings.json"])
    }

    /// A v1 file with nothing but its version has nothing to lose: it loads as defaults, is backed up
    /// like any v1 file, and is rewritten as v2. Nothing is quarantined.
    @Test func sparseV1LoadsWithDefaultsAndIsMigrated() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let bytes = Data(#"{"schemaVersion":1,"defaultGap":5}"#.utf8)
        try bytes.write(to: file)

        let result = await makeStore(dir).load()
        var expected = TesseraSettings.defaults
        expected.defaultGap = 5
        #expect(result.settings == expected)
        #expect(result.recoveredFrom == nil)
        #expect(try Data(contentsOf: dir.appendingPathComponent("settings.v1-backup.json")) == bytes)
        #expect(try JSONDecoder().decode(TesseraSettings.self, from: Data(contentsOf: file)) == expected)
    }

    @Test func invalidValuesInAV1FileAreStillSetAside() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let bytes = Data(#"{"schemaVersion":1,"trigger":{"keyCodes":[]}}"#.utf8)
        try bytes.write(to: file)

        let result = await makeStore(dir).load()
        #expect(result.settings == .defaults)
        let moved = try #require(result.recoveredFrom)
        #expect(try Data(contentsOf: moved) == bytes)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.v1-backup.json").path))
    }

    @Test func importAcceptsAnM1ExportAndMigratesIt() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("m1-export.json")
        try v1Data(from: userSettings()).write(to: file)

        let imported = try await makeStore(dir).importSettings(from: file)
        var expected = userSettings()
        expected.schemaVersion = 2
        #expect(imported == expected)
    }
}
