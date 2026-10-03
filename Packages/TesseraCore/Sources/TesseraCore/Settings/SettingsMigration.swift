import Foundation

/// Upgrades settings JSON written by an older build (M2 spec §7). Works on the raw JSON so no
/// user value is ever re-derived: it only adds the keys the older file lacks.
public enum SettingsMigration {
    /// Keys added by schema v2. Their values come from `TesseraSettings.defaults`.
    private static let v2Keys = ["hotkeys", "cycles", "ringKeyNavigation", "announceSelection"]

    /// v1 JSON gets the v2 keys with default values (existing ones are kept) and `schemaVersion: 2`.
    /// Anything else comes back untouched with `migratedFrom == nil`; the decoder and validation decide
    /// whether it is usable. Throws only when `data` is not a JSON object.
    public static func migrate(_ data: Data) throws -> (data: Data, migratedFrom: Int?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalid("Settings file is not a JSON object.")
        }
        guard object["schemaVersion"] as? Int == 1 else { return (data, nil) }

        let defaults = try JSONEncoder().encode(TesseraSettings.defaults)
        let defaultObject = (try JSONSerialization.jsonObject(with: defaults) as? [String: Any]) ?? [:]

        var migrated = object
        for key in v2Keys where migrated[key] == nil { migrated[key] = defaultObject[key] }
        migrated["schemaVersion"] = 2
        return (try JSONSerialization.data(withJSONObject: migrated, options: [.prettyPrinted, .sortedKeys]), 1)
    }
}
