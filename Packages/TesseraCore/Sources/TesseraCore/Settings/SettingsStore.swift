import Foundation

/// Loads, saves, exports and imports `settings.json` (spec §6.4, §7).
///
/// Data-loss rule: a file that cannot be used is moved aside or copied first, never overwritten or deleted.
/// Not for hot paths; callers keep their own in-memory copy.
public actor SettingsStore {
    private let fileURL: URL
    private let now: @Sendable () -> Date
    /// Set by `load()` when the file on disk must survive this session; `save` then refuses.
    private var saveRefusal: SaveRefusal?

    /// `now` is only used to name quarantined files and repair copies; it is injectable for tests.
    public init(fileURL: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    /// Missing file gives defaults. A v1 file is migrated (M2 spec §7): the original bytes are copied to
    /// `settings.v1-backup.json` (never overwriting an existing backup; a numbered name is used instead),
    /// then v2 is saved. Keys a file lacks take their default values (see `SettingsMigration`).
    ///
    /// A value this build can't read or that is out of range is repaired on its own (see `decode`); the original
    /// bytes are first copied to `settings.pre-repair-<yyyyMMdd-HHmmss>.json` (UTC). A file that is not a settings
    /// object at all is moved to `settings.corrupt-<stamp>.json` and gives defaults. A newer schema, a read
    /// error, or a bad file that could not be moved or copied gives defaults and leaves the file as it is, and
    /// `save` refuses for the session (`LoadResult.saveRefusal`) so nothing is lost.
    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(settings: .defaults, recoveredFrom: nil)
        }
        let original: Data
        do {
            original = try Data(contentsOf: fileURL)
        } catch {
            return refuse(.unreadable)
        }
        if let version = Self.schemaVersion(of: original), version > SettingsValidation.currentSchemaVersion {
            return refuse(.newerSchema(version))
        }
        let decoded: (settings: TesseraSettings, migratedFrom: Int?, repairs: [String])
        do {
            decoded = try Self.decode(original)
        } catch {
            let moved = setAside()
            if moved == nil { saveRefusal = .notSetAside }
            return LoadResult(settings: .defaults, recoveredFrom: moved, saveRefusal: saveRefusal)
        }
        var repairBackup: URL?
        if !decoded.repairs.isEmpty {
            repairBackup = copyOriginal(original, as: "settings.pre-repair-\(Self.timestamp(now()))")
            if repairBackup == nil { saveRefusal = .noRepairBackup }
        }
        // Only touch the file once the migrated result is known to be usable. If the backup cannot be
        // written the v1 file stays as it is and migrates again next launch.
        if decoded.migratedFrom != nil, saveRefusal == nil, copyOriginal(original, as: "settings.v1-backup") != nil {
            try? Self.write(decoded.settings, to: fileURL, createFolder: false)
        }
        return LoadResult(settings: decoded.settings, recoveredFrom: nil, repairs: decoded.repairs,
                          repairBackup: repairBackup, saveRefusal: saveRefusal)
    }

    /// The one path from file bytes to usable settings: migrate, decode, repair, validate. `repairs` names each
    /// value reset or item dropped on the way (see `LenientSettingsDecoder` and `SettingsValidation.repair`).
    /// Throws `SettingsError.invalid` with a message safe to show. Used by `load`, `importSettings` and the UI.
    public static func decode(_ data: Data) throws -> (settings: TesseraSettings, migratedFrom: Int?, repairs: [String]) {
        // A file with no "help" key predates help settings: offer it the ⌃⌥/ default once.
        let predatesHelp = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["help"] == nil
        // Without a version this build reads there is nothing to repair towards: the file is not usable.
        let version = schemaVersion(of: data) ?? 0
        if version > SettingsValidation.currentSchemaVersion {
            throw SettingsError.invalid("These settings were saved by a newer version of Tessera.")
        }
        guard version >= 1 else { throw SettingsError.invalid("Not a valid Tessera settings file.") }
        let migration = try SettingsMigration.migrate(data)
        let decoded = try LenientSettingsDecoder.decode(migration.data)
        let repaired = SettingsValidation.repair(decoded.settings)
        try SettingsValidation.validate(repaired.settings)
        let settings = predatesHelp ? HelpDefaults.offeringExplainHotkey(repaired.settings) : repaired.settings
        return (settings, migration.migratedFrom, decoded.repairs + repaired.repairs)
    }

    /// The file's `schemaVersion`, or nil when it is not a JSON object with an integer version.
    static func schemaVersion(of data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int
    }

    /// Atomic write; creates the folder if needed. Invalid settings are refused so a bad value can
    /// never turn the next launch into a recovery.
    /// Throws `SaveRefusal` without writing when `load()` found a file this session must not overwrite.
    public func save(_ s: TesseraSettings) throws {
        if let saveRefusal { throw saveRefusal }
        try SettingsValidation.validate(s)
        try Self.write(s, to: fileURL, createFolder: true)
    }

    public func export(_ s: TesseraSettings, to url: URL) throws {
        try SettingsValidation.validate(s)
        try Self.write(s, to: url, createFolder: false)
    }

    /// Validates before returning. Throws `.invalid(firstProblem)` and touches nothing on disk.
    public func importSettings(from url: URL) throws -> TesseraSettings {
        let name = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SettingsError.invalid("Could not read \(name): \(error.localizedDescription)")
        }
        do {
            return try Self.decode(data).settings
        } catch SettingsError.invalid(let problem) {
            throw SettingsError.invalid("\(name): \(problem)")
        }
    }

    // MARK: Private

    private static func write(_ s: TesseraSettings, to url: URL, createFolder: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(s)
        if createFolder {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
        try data.write(to: url, options: .atomic)
    }

    private func refuse(_ reason: SaveRefusal) -> LoadResult {
        saveRefusal = reason
        return LoadResult(settings: .defaults, recoveredFrom: nil, saveRefusal: reason)
    }

    /// Copies `original` next to the settings file as `<name>.json`, or `<name>-1.json` and so on when taken.
    /// Never overwrites. Nil when no copy could be written.
    private func copyOriginal(_ original: Data, as name: String) -> URL? {
        guard let destination = freeName(name) else { return nil }
        return (try? original.write(to: destination, options: .withoutOverwriting)) != nil ? destination : nil
    }

    /// Moves the unusable file to `settings.corrupt-<stamp>.json`. Nil when it could not be moved, so the caller
    /// never reports a path as preserved that isn't.
    private func setAside() -> URL? {
        guard let destination = freeName("settings.corrupt-\(Self.timestamp(now()))") else { return nil }
        return (try? FileManager.default.moveItem(at: fileURL, to: destination)) != nil ? destination : nil
    }

    /// The first unused of `<name>.json`, `<name>-1.json` … `<name>-99.json` beside the settings file. A numeric
    /// suffix keeps two copies made in the same second from clobbering each other.
    private func freeName(_ name: String) -> URL? {
        let folder = fileURL.deletingLastPathComponent()
        return (0..<100).lazy
            .map { folder.appendingPathComponent("\(name)\($0 == 0 ? "" : "-\($0)").json") }
            .first { !FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
