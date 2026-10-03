import Foundation

/// Loads, saves, exports and imports `settings.json` (spec §6.4, §7).
///
/// Data-loss rule: a file that cannot be used is moved aside, never overwritten or deleted.
/// Not for hot paths; callers keep their own in-memory copy.
public actor SettingsStore {
    public struct LoadResult: Sendable {
        public let settings: TesseraSettings
        /// Where the unusable file now lives, when `load()` had to set one aside.
        /// If the move itself failed this is the original URL (the bad file is still in place).
        public let recoveredFrom: URL?

        public init(settings: TesseraSettings, recoveredFrom: URL?) {
            self.settings = settings
            self.recoveredFrom = recoveredFrom
        }
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date

    /// `now` is only used to name quarantined files; it is injectable for tests.
    public init(fileURL: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    /// Missing file gives defaults. A v1 file is migrated (M2 spec §7): the original bytes are copied to
    /// `settings.v1-backup.json` (never overwriting an existing backup; a numbered name is used instead),
    /// then v2 is saved. Unreadable JSON, a newer schema or failed validation moves the file to
    /// `settings.corrupt-<yyyyMMdd-HHmmss>.json` (UTC) next to it and gives defaults.
    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(settings: .defaults, recoveredFrom: nil)
        }
        do {
            let original = try Data(contentsOf: fileURL)
            let migration = try SettingsMigration.migrate(original)
            let settings = try JSONDecoder().decode(TesseraSettings.self, from: migration.data)
            try SettingsValidation.validate(settings)
            // Only touch the file once the migrated result is known to be usable. If the backup cannot be
            // written the v1 file stays as it is and migrates again next launch.
            if migration.migratedFrom != nil, writeV1Backup(original) {
                try? Self.write(settings, to: fileURL, createFolder: false)
            }
            return LoadResult(settings: settings, recoveredFrom: nil)
        } catch {
            return LoadResult(settings: .defaults, recoveredFrom: setAsideUnusableFile())
        }
    }

    /// Atomic write; creates the folder if needed. Invalid settings are refused so a bad value can
    /// never turn the next launch into a recovery.
    public func save(_ s: TesseraSettings) throws {
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
        let settings: TesseraSettings
        do {
            settings = try JSONDecoder().decode(TesseraSettings.self, from: SettingsMigration.migrate(data).data)
        } catch {
            throw SettingsError.invalid("\(name) is not a valid Tessera settings file, or comes from a newer version.")
        }
        try SettingsValidation.validate(settings)
        return settings
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

    /// Copies the v1 bytes next to the settings file. Returns false when no backup could be written.
    private func writeV1Backup(_ original: Data) -> Bool {
        let fm = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt)"
            let destination = folder.appendingPathComponent("settings.v1-backup\(suffix).json")
            if fm.fileExists(atPath: destination.path) { continue }
            return (try? original.write(to: destination, options: .withoutOverwriting)) != nil
        }
        return false
    }

    private func setAsideUnusableFile() -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        let folder = fileURL.deletingLastPathComponent()
        let stamp = Self.timestamp(now())
        // A numeric suffix keeps two recoveries in the same second from clobbering each other.
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt)"
            let destination = folder.appendingPathComponent("settings.corrupt-\(stamp)\(suffix).json")
            if fm.fileExists(atPath: destination.path) { continue }
            do {
                try fm.moveItem(at: fileURL, to: destination)
                return destination
            } catch {
                break
            }
        }
        return fileURL
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
