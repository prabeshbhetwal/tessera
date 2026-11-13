import Foundation
import Testing
@testable import TesseraCore

@Suite struct SettingsReplacementTests {
    @Test func importingPreservesThePreviousSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: file)
        var previous = TesseraSettings.defaults
        previous.hudSeconds = 3
        try await store.save(previous)
        let original = try Data(contentsOf: file)
        var imported = previous
        imported.hudSeconds = 5
        try await store.replace(with: imported)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.before-import-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(await store.load().settings.hudSeconds == 5)
    }
    @Test func firstImportPreservesInMemoryDefaultsBeforeCreatingSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SettingsStore(fileURL: directory.appendingPathComponent("Tessera/settings.json"))
        var imported = TesseraSettings.defaults
        imported.hudSeconds = 5
        try await store.replace(with: imported, previous: .defaults)
        #expect(await store.load().settings.hudSeconds == 5)
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Tessera"), includingPropertiesForKeys: nil)
        let backup = try #require(files.first { $0.lastPathComponent.hasPrefix("settings.before-import-") })
        #expect(try SettingsStore.decode(Data(contentsOf: backup)).settings == .defaults)
    }

    @Test func invalidImportCannotReplaceThePreviousFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: file)
        try await store.save(.defaults)
        let original = try Data(contentsOf: file)
        var invalid = TesseraSettings.defaults
        invalid.schemaVersion = 999
        await #expect(throws: SettingsError.self) { try await store.replace(with: invalid) }
        #expect(try Data(contentsOf: file) == original)
    }
}
