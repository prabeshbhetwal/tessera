import Foundation
import Testing
@testable import TesseraCore

@Suite struct SettingsStoreTests {
    /// 1970-01-01 01:01:01 UTC, so the quarantine name is deterministic.
    private static let fixedNow = Date(timeIntervalSince1970: 3661)
    private static let quarantineName = "settings.corrupt-19700101-010101.json"

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore(in dir: URL, file: String = "settings.json") -> SettingsStore {
        SettingsStore(fileURL: dir.appendingPathComponent(file), now: { Self.fixedNow })
    }

    private func customised() -> TesseraSettings {
        var s = TesseraSettings.defaults
        s.defaultGap = 12
        s.ring.deadZone = 14
        s.ring.wedges[0] = .topHalf
        s.preview.opacity = 0.6
        s.themeName = "Glass"
        s.excludedBundleIDs = ["com.apple.Terminal"]
        s.displayOverrides["1-2-3"] = DisplayProfile(columns: 4, gap: 6, padding: 10, isUserOverride: true)
        return s
    }

    // MARK: Load

    @Test func testMissingFileGivesDefaults() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)

        let result = await store.load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == nil)
        // Loading must not create the file.
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path))
    }

    @Test func testSaveLoadRoundTrip() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)
        let settings = customised()

        try await store.save(settings)
        let result = await store.load()
        #expect(result.settings == settings)
        #expect(result.recoveredFrom == nil)
    }

    @Test func testSaveCreatesMissingFolder() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Nested/Tessera/settings.json")
        let store = SettingsStore(fileURL: file, now: { Self.fixedNow })

        try await store.save(.defaults)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func testCorruptFileRenamed() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let garbage = Data("{ not json at all".utf8)
        try garbage.write(to: file)

        let result = await makeStore(in: dir).load()
        let moved = dir.appendingPathComponent(Self.quarantineName)
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == moved)
        #expect(try Data(contentsOf: moved) == garbage, "original bytes must be preserved")
        #expect(!FileManager.default.fileExists(atPath: file.path), "must not silently recreate settings.json")
    }

    @Test func testTruncatedJSONRenamed() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)
        try await store.save(customised())
        let file = dir.appendingPathComponent("settings.json")
        let full = try Data(contentsOf: file)
        let truncated = full.prefix(full.count / 2)
        try truncated.write(to: file)

        let result = await store.load()
        let moved = dir.appendingPathComponent(Self.quarantineName)
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == moved)
        #expect(try Data(contentsOf: moved) == truncated)
    }

    @Test func testNewerSchemaRenamed() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        var newer = TesseraSettings.defaults
        newer.schemaVersion = 2
        let bytes = try JSONEncoder().encode(newer)
        try bytes.write(to: file)

        let result = await makeStore(in: dir).load()
        let moved = dir.appendingPathComponent(Self.quarantineName)
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == moved)
        #expect(try Data(contentsOf: moved) == bytes)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func testMissingKeyTreatedAsCorrupt() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try Data(#"{"schemaVersion":1}"#.utf8).write(to: file)

        let result = await makeStore(in: dir).load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom != nil)
    }

    @Test func testInvalidSettingsOnDiskRenamed() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        var bad = TesseraSettings.defaults
        bad.ring.wedges.removeLast()
        try JSONEncoder().encode(bad).write(to: file)

        let result = await makeStore(in: dir).load()
        #expect(result.settings == .defaults)
        #expect(result.recoveredFrom == dir.appendingPathComponent(Self.quarantineName))
    }

    @Test func testQuarantineNeverOverwritesEarlierQuarantine() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let store = makeStore(in: dir)

        try Data("first".utf8).write(to: file)
        let first = await store.load().recoveredFrom
        try Data("second".utf8).write(to: file)
        let second = await store.load().recoveredFrom

        #expect(first != nil && second != nil && first != second)
        #expect(try first.map { try Data(contentsOf: $0) } == Data("first".utf8))
        #expect(try second.map { try Data(contentsOf: $0) } == Data("second".utf8))
    }

    // MARK: Export / import

    @Test func testExportImportEqual() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)
        let settings = customised()
        let exported = dir.appendingPathComponent("export.json")

        try await store.export(settings, to: exported)
        let imported = try await store.importSettings(from: exported)
        #expect(imported == settings)
    }

    @Test func testInvalidImportRejectedUntouched() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)
        let original = customised()
        try await store.save(original)
        let file = dir.appendingPathComponent("settings.json")
        let before = try Data(contentsOf: file)

        var sevenWedges = TesseraSettings.defaults
        sevenWedges.ring.wedges.removeLast()
        let importFile = dir.appendingPathComponent("import.json")
        try JSONEncoder().encode(sevenWedges).write(to: importFile)

        await #expect(throws: SettingsError.self) {
            _ = try await store.importSettings(from: importFile)
        }
        #expect(try Data(contentsOf: file) == before)
        let listing = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(listing == ["import.json", "settings.json"])
        #expect(await store.load().settings == original)
    }

    @Test func testImportRejectsMalformedAndMissingFiles() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)

        let junk = dir.appendingPathComponent("junk.json")
        try Data("nope".utf8).write(to: junk)
        await #expect(throws: SettingsError.self) { _ = try await store.importSettings(from: junk) }
        await #expect(throws: SettingsError.self) {
            _ = try await store.importSettings(from: dir.appendingPathComponent("absent.json"))
        }
    }

    @Test func testImportRejectsNewerSchema() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)
        var newer = TesseraSettings.defaults
        newer.schemaVersion = 2
        let file = dir.appendingPathComponent("newer.json")
        try JSONEncoder().encode(newer).write(to: file)

        await #expect(throws: SettingsError.self) { _ = try await store.importSettings(from: file) }
    }

    @Test func testSaveRejectsInvalidSettingsWithoutWriting() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(in: dir)
        var bad = TesseraSettings.defaults
        bad.trigger = TriggerChord(keyCodes: [])

        await #expect(throws: SettingsError.self) { try await store.save(bad) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path))
    }

    // MARK: Validation

    private func firstProblem(_ s: TesseraSettings) -> String? {
        do {
            try SettingsValidation.validate(s)
            return nil
        } catch let SettingsError.invalid(message) {
            return message
        } catch {
            return "unexpected error type: \(error)"
        }
    }

    @Test func testDefaultsAreValid() {
        #expect(firstProblem(.defaults) == nil)
        #expect(firstProblem(customised()) == nil)
    }

    @Test func testValidationRejects() {
        let cases: [(String, (inout TesseraSettings) -> Void)] = [
        ("wedges 7", { (s: inout TesseraSettings) in s.ring.wedges.removeLast() }),
        ("wedges 9", { (s: inout TesseraSettings) in s.ring.wedges.append(.center) }),
        ("min width 0", { (s: inout TesseraSettings) in s.sizing.minColumnWidth = 0 }),
        ("min > ideal", { (s: inout TesseraSettings) in s.sizing.minColumnWidth = 800 }),
        ("ideal > max", { (s: inout TesseraSettings) in s.sizing.idealColumnWidth = 1300 }),
        ("maxColumns 0", { (s: inout TesseraSettings) in s.sizing.maxColumns = 0 }),
        ("maxColumns 17", { (s: inout TesseraSettings) in s.sizing.maxColumns = 17 }),
        ("deadZone negative", { (s: inout TesseraSettings) in s.ring.deadZone = -1 }),
        ("deadZone == flick", { (s: inout TesseraSettings) in s.ring.deadZone = 90 }),
        ("deadZone > flick", { (s: inout TesseraSettings) in s.ring.deadZone = 100 }),
        ("bands sum 1", { (s: inout TesseraSettings) in s.ring.topBand = 0.5; s.ring.bottomBand = 0.5 }),
        ("override 0 columns", { (s: inout TesseraSettings) in
            s.displayOverrides["x"] = DisplayProfile(columns: 0, isUserOverride: true)
        }),
        ("empty chord", { (s: inout TesseraSettings) in s.trigger = TriggerChord(keyCodes: []) }),
        ("schema 0", { (s: inout TesseraSettings) in s.schemaVersion = 0 }),
        ("schema 2", { (s: inout TesseraSettings) in s.schemaVersion = 2 }),
        ]
        for (name, mutate) in cases {
            var s = TesseraSettings.defaults
            mutate(&s)
            #expect(firstProblem(s) != nil, "\(name) should be rejected")
        }
    }

    @Test func testValidationBoundariesAccepted() {
        var s = TesseraSettings.defaults
        s.sizing.minColumnWidth = 700
        s.sizing.idealColumnWidth = 700
        s.sizing.maxColumnWidth = 700
        s.sizing.maxColumns = 1
        s.ring.deadZone = 0
        s.ring.topBand = 0.49
        s.ring.bottomBand = 0.5
        #expect(firstProblem(s) == nil)
        s.sizing.maxColumns = 16
        #expect(firstProblem(s) == nil)
    }

    @Test func testValidationReportsFirstProblemDeterministically() {
        var s = TesseraSettings.defaults
        s.ring.wedges.removeLast()
        s.trigger = TriggerChord(keyCodes: [])
        let first = firstProblem(s)
        #expect(first?.contains("wedge") == true)
        #expect(firstProblem(s) == first)
    }
}
