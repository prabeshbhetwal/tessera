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

    @Test func unusableV1IsSetAsideNotBackedUpNorOverwritten() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let bytes = Data(#"{"schemaVersion":1}"#.utf8)
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
