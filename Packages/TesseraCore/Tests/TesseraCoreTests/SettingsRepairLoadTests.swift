import Foundation
import Testing
@testable import TesseraCore

/// A repaired file is repaired once: adjacent bad items all go, the fixed settings are written back after the
/// original is copied, and an import reports what it fixed (audit: repair loop, repair alert on every launch).
@Suite struct SettingsRepairLoadTests {
    private static let fixedNow = Date(timeIntervalSince1970: 3661)
    private static let repairCopyName = "settings.pre-repair-19700101-010101.json"

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-repair-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore(in dir: URL) -> SettingsStore {
        SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), now: { Self.fixedNow })
    }

    /// The default settings as JSON, edited by `edit`.
    private func edited(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Adjacent bad items

    /// Removing one bad hotkey slides the next into its index; that is progress, not a loop.
    @Test(arguments: [2, 3])
    func adjacentUnreadableHotkeysAreAllRemoved(count: Int) throws {
        let data = try edited { object in
            var hotkeys = object["hotkeys"] as? [[String: Any]] ?? []
            for i in 0..<count { hotkeys[i]["command"] = ["teleport": [String: Any]()] }
            object["hotkeys"] = hotkeys
        }

        let decoded = try SettingsStore.decode(data)
        #expect(decoded.settings.hotkeys == Array(HotkeyBinding.defaults.dropFirst(count)))
        let removed = decoded.repairs.filter { $0.hasPrefix("Removed the hotkey ") }
        #expect(removed == HotkeyBinding.defaults.prefix(count)
            .map { "Removed the hotkey “\($0.id)”, which this version can’t read." })
    }

    @Test func aBadValueThatStaysBadStillGivesUp() {
        // Not an object at the root: no path to repair, so the file is unusable rather than looping.
        #expect(throws: SettingsError.self) { try SettingsStore.decode(Data("[]".utf8)) }
    }

    // MARK: Repair written back

    @Test func aRepairedFileIsFixedOnDiskSoLaterLoadsAreQuiet() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let bytes = try edited { $0["hudPosition"] = "sideways" }
        try bytes.write(to: file)

        let first = await makeStore(in: dir).load()
        #expect(first.repairs == ["Reset the message position to its default."])
        #expect(first.repairBackup == dir.appendingPathComponent(Self.repairCopyName))
        #expect(first.notice?.title == "Some settings were repaired")
        #expect(first.settings == .defaults)

        // A relaunch: a new store reads the same file.
        let second = await makeStore(in: dir).load()
        #expect(second.settings == .defaults)
        #expect(second.repairs.isEmpty)
        #expect(second.repairBackup == nil)
        #expect(second.notice == nil)

        let listing = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(listing == ["settings.json", Self.repairCopyName], "one repair notice, one copy in total")
        #expect(try Data(contentsOf: dir.appendingPathComponent(Self.repairCopyName)) == bytes)
        #expect(try JSONDecoder().decode(TesseraSettings.self, from: Data(contentsOf: file)) == .defaults)
    }

    // MARK: Import reports its repairs

    @Test func importReturnsWhatItRepaired() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dirty = dir.appendingPathComponent("dirty.json")
        try edited { $0["hudPosition"] = "sideways" }.write(to: dirty)
        let clean = dir.appendingPathComponent("clean.json")
        try JSONEncoder().encode(TesseraSettings.defaults).write(to: clean)
        let store = makeStore(in: dir)

        let imported = try await store.importSettings(from: dirty)
        #expect(imported.settings == .defaults)
        #expect(imported.repairs == ["Reset the message position to its default."])
        #expect(try await store.importSettings(from: clean).repairs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["clean.json", "dirty.json"])
    }

    @Test func repairListShowsFiveThenCountsTheRest() {
        let repairs = (1...7).map { "Fix \($0)." }
        let list = SettingsStore.LoadResult.repairList(repairs)
        #expect(list == "\n\n• Fix 1.\n• Fix 2.\n• Fix 3.\n• Fix 4.\n• Fix 5.\nand 2 more.")
        #expect(SettingsStore.LoadResult.repairList([]) == "")
    }
}
