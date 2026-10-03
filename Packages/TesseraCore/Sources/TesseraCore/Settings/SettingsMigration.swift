import Foundation

/// Upgrades settings JSON written by an older build, or repaired by hand (M2 spec §7). Works on the raw
/// JSON so no user value is ever re-derived: it only adds the keys the file lacks, taking their values
/// from `TesseraSettings.defaults`, and brings `schemaVersion` up to date.
///
/// Because every missing key is filled, a new setting needs no schema bump and no Optional: give it a
/// default in `TesseraSettings` and older files load with that default.
public enum SettingsMigration {
    /// Any file whose `schemaVersion` this build can read (1...current) comes back complete. `migratedFrom`
    /// is the old version when it changed, nil when only missing keys were filled or nothing was done.
    /// A missing, non-integer or newer version comes back untouched with `migratedFrom == nil`; the
    /// decoder and validation decide whether it is usable. Throws only when `data` is not a JSON object.
    public static func migrate(_ data: Data) throws -> (data: Data, migratedFrom: Int?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalid("Settings file is not a JSON object.")
        }
        let current = SettingsValidation.currentSchemaVersion
        guard let version = object["schemaVersion"] as? Int, (1...current).contains(version) else { return (data, nil) }

        let defaults = try JSONEncoder().encode(TesseraSettings.defaults)
        let defaultObject = (try JSONSerialization.jsonObject(with: defaults) as? [String: Any]) ?? [:]

        var filled = object
        var added = fill(&filled, from: defaultObject)
        // Arrays of objects have no default element to copy from, so name a template for each.
        for (key, template) in try elementTemplates() {
            guard var elements = filled[key] as? [[String: Any]] else { continue }
            for i in elements.indices {
                // A theme saved before the preview had its own colour kept using its accent; keep that look.
                if key == "customThemes", elements[i]["previewHex"] == nil, let accent = elements[i]["accentHex"] {
                    elements[i]["previewHex"] = accent
                    added = true
                }
                if fill(&elements[i], from: template) { added = true }
            }
            filled[key] = elements
        }
        guard added || version < current else { return (data, nil) }
        filled["schemaVersion"] = current
        let bytes = try JSONSerialization.data(withJSONObject: filled, options: [.prettyPrinted, .sortedKeys])
        return (bytes, version < current ? version : nil)
    }

    /// Missing keys inside each custom theme come from the Default theme (its `name` is never missing).
    private static func elementTemplates() throws -> [String: [String: Any]] {
        let theme = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Theme.default)) as? [String: Any]
        return ["customThemes": theme ?? [:]]
    }

    /// Adds every key of `defaults` that `object` lacks and recurses into nested objects. Arrays and
    /// user-keyed maps (display overrides) are left as they are. True when anything was added.
    private static func fill(_ object: inout [String: Any], from defaults: [String: Any]) -> Bool {
        var added = false
        for (key, value) in defaults {
            if object[key] == nil {
                object[key] = value
                added = true
            } else if var nested = object[key] as? [String: Any], let nestedDefaults = value as? [String: Any],
                      fill(&nested, from: nestedDefaults) {
                object[key] = nested
                added = true
            }
        }
        return added
    }
}
