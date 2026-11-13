import Foundation

extension SettingsStore {
    /// Why `save` refuses for the rest of the session: the file on disk holds settings that must not be overwritten.
    /// `save` throws this same value.
    public enum SaveRefusal: Error, Equatable, Sendable {
        /// Written by a newer Tessera (the schema version it carries). Kept for when the person upgrades again.
        case newerSchema(Int)
        /// The file is there but could not be read: an I/O error, or a cloud placeholder not yet downloaded.
        case unreadable
        /// The file could not be used and could not be moved aside either, so it is still in place.
        case notSetAside
        /// Load repaired the file but could not keep a copy of the original.
        case noRepairBackup
    }

    public struct LoadResult: Sendable {
        public let settings: TesseraSettings
        /// Where the unusable file now lives, when `load()` set one aside. Nil when nothing was moved, including
        /// when the move failed (then `saveRefusal` is `.notSetAside`).
        public let recoveredFrom: URL?
        /// What load fixed in a file it could otherwise use, one sentence each: values back to their defaults or
        /// into range, and items this version can't read removed.
        public let repairs: [String]
        /// The copy of the file as it was before `repairs`.
        public let repairBackup: URL?
        /// Set when this session must not save over the file.
        public let saveRefusal: SaveRefusal?

        public init(settings: TesseraSettings, recoveredFrom: URL?, repairs: [String] = [], repairBackup: URL? = nil,
                    saveRefusal: SaveRefusal? = nil) {
            self.settings = settings
            self.recoveredFrom = recoveredFrom
            self.repairs = repairs
            self.repairBackup = repairBackup
            self.saveRefusal = saveRefusal
        }
    }
}

extension SettingsStore.LoadResult {
    /// The alert to show after this load, or nil when there is nothing to tell the person.
    public var notice: (title: String, message: String)? {
        let notSaved = "changes made now are not saved."
        switch saveRefusal {
        case .newerSchema:
            return ("Settings from a newer Tessera",
                    "These settings were saved by a newer version of Tessera. They are left untouched, and \(notSaved)")
        case .unreadable:
            return ("Settings couldn’t be read",
                    "Tessera couldn’t open its settings file, so it started with defaults. The file is left untouched, and \(notSaved)")
        case .notSetAside:
            return ("Settings were reset",
                    "Tessera couldn’t use its settings file, so it started with defaults. The file is left in place, and \(notSaved)")
        case .noRepairBackup:
            return ("Some settings were repaired",
                    "Tessera fixed settings it couldn’t use, but couldn’t keep a copy of the original file, so \(notSaved)"
                        + Self.repairList(repairs))
        case nil:
            break
        }
        if let recoveredFrom {
            return ("Settings were reset", "Tessera couldn’t read its settings file, so it started with defaults. "
                + "The old file was kept at \(recoveredFrom.path).")
        }
        guard !repairs.isEmpty, let repairBackup else { return nil }
        let what = repairs.count == 1 ? "1 setting" : "\(repairs.count) settings"
        return ("Some settings were repaired", "Tessera fixed \(what) it couldn’t use and kept everything else. "
            + "A copy of the original file was kept at \(repairBackup.path)." + Self.repairList(repairs))
    }

    /// The first five repairs, one per line, then "and N more.", ready to follow a message; empty when there are none.
    /// Shared by the launch notice and the import confirmation.
    public static func repairList(_ repairs: [String]) -> String {
        guard !repairs.isEmpty else { return "" }
        let shown = repairs.prefix(5).map { "• \($0)" }
        let more = repairs.count > 5 ? ["and \(repairs.count - 5) more."] : []
        return "\n\n" + (shown + more).joined(separator: "\n")
    }
}
