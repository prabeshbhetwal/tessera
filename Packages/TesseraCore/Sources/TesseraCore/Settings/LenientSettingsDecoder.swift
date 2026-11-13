import Foundation

/// Decodes settings JSON so one value this build can't read costs only that value, not the whole file (a file
/// written by a newer beta after a rollback, or a hand edit slightly wrong). Each failed decode names the bad value's
/// path: the value goes back to its default, or the user item holding it (a hotkey, a theme, …) is dropped, and
/// decoding runs again. Works on the raw JSON like `SettingsMigration`, so the model types keep synthesised Codable
/// and a valid file decodes exactly as before.
enum LenientSettingsDecoder {
    /// Top-level lists and maps of things the user made, with the name of one element. A bad element is dropped
    /// (or, for a key with an obvious default, given that default), never the whole list.
    private static let items: [String: String] = [
        "hotkeys": "hotkey", "cycles": "cycle", "customThemes": "custom theme", "learnedSplits": "learned split",
        "excludedBundleIDs": "excluded app", "displayOverrides": "display setting",
    ]

    private static var unreadable: SettingsError {
        .invalid("Not a valid Tessera settings file, or one from a newer version.")
    }

    /// `repairs` is empty when `data` decoded as it is. Throws `SettingsError.invalid` when `data` is not a JSON
    /// object or a bad value has neither a default nor an item to drop.
    static func decode(_ data: Data) throws -> (settings: TesseraSettings, repairs: [String]) {
        let decoder = JSONDecoder()
        if let settings = try? decoder.decode(TesseraSettings.self, from: data) { return (settings, []) }
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw unreadable }
        let defaults = try jsonObject(TesseraSettings.defaults)
        let templates = try elementTemplates()
        var repairs: [String] = []
        var lastPath: [String]?
        // Each pass repairs one value; a pass that fails at the same place again made no progress.
        while true {
            do {
                let bytes = try JSONSerialization.data(withJSONObject: root)
                return (try decoder.decode(TesseraSettings.self, from: bytes), repairs)
            } catch let error as DecodingError {
                guard let path = failingPath(error), path.map(\.stringValue) != lastPath,
                      let repair = repair(&root, at: path, defaults: defaults, templates: templates)
                else { throw unreadable }
                lastPath = path.map(\.stringValue)
                repairs.append(repair)
            } catch {
                throw unreadable
            }
        }
    }

    /// The path of the value that failed, including a missing key's own name.
    private static func failingPath(_ error: DecodingError) -> [any CodingKey]? {
        switch error {
        case let .keyNotFound(key, context):
            let path = context.codingPath
            return path.last?.stringValue == key.stringValue ? path : path + [key]
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return context.codingPath.isEmpty ? nil : context.codingPath
        @unknown default:
            return nil
        }
    }

    private static func repair(_ root: inout [String: Any], at path: [any CodingKey], defaults: [String: Any],
                               templates: [String: [String: Any]]) -> String? {
        let first = path[0].stringValue
        if let item = items[first], path.count >= 2 {
            let element = path.prefix(2)
            let inner = path.dropFirst(2)
            let name = describe(item, value(at: element, in: root))
            if !inner.isEmpty, let fallback = value(at: inner, in: templates[first] ?? [:]) {
                root = set(root, at: path[...], to: fallback) as? [String: Any] ?? root
                return "Reset \(dotted(inner)) in \(name) to its default."
            }
            root = set(root, at: element, to: nil) as? [String: Any] ?? root
            return "Removed \(name), which this version can’t read."
        }
        if let fallback = value(at: path[...], in: defaults) {
            root = set(root, at: path[...], to: fallback) as? [String: Any] ?? root
            return "Reset \(dotted(path[...])) to its default."
        }
        // A list element with no default at its index (a ninth wedge, a stray keycode) leaves its list; the
        // list's own repair (`SettingsValidation.repair`) then deals with the count.
        guard let index = path.indices.last(where: { value(at: path.prefix($0), in: root) is [Any] }) else { return nil }
        root = set(root, at: path.prefix(index + 1), to: nil) as? [String: Any] ?? root
        return "Removed an unreadable entry from \(dotted(path.prefix(index)))."
    }

    /// Defaults for keys inside one user item that have an obvious value; any other bad key drops the item.
    private static func elementTemplates() throws -> [String: [String: Any]] {
        var display = try jsonObject(DisplayProfile(columns: 1))
        display["columns"] = nil
        let binding = try jsonObject(HotkeyBinding(id: "", hotkey: Hotkey(keyCode: 0, modifiers: []), command: .undo))
        let cycle = try jsonObject(Cycle(name: "", steps: []))
        return [
            "customThemes": try jsonObject(Theme.default),
            "displayOverrides": display,
            "hotkeys": ["enabled": binding["enabled"] ?? true],
            "cycles": ["display": cycle["display"] ?? [String: Any]()],
        ]
    }

    private static func describe(_ item: String, _ element: Any?) -> String {
        let object = element as? [String: Any]
        if let name = (object?["id"] ?? object?["name"] ?? element) as? String, !name.isEmpty {
            return "the \(item) “\(name)”"
        }
        return ("aeiou".contains(item.first ?? "x") ? "an " : "a ") + item
    }

    private static func dotted(_ path: ArraySlice<any CodingKey>) -> String {
        path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    private static func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]) ?? [:]
    }

    /// Follows `path` through objects and arrays. A map key that looks like a number is still looked up by name.
    private static func value(at path: ArraySlice<any CodingKey>, in node: Any) -> Any? {
        guard let key = path.first else { return node }
        if let array = node as? [Any] {
            guard let i = key.intValue, array.indices.contains(i) else { return nil }
            return value(at: path.dropFirst(), in: array[i])
        }
        guard let child = (node as? [String: Any])?[key.stringValue] else { return nil }
        return value(at: path.dropFirst(), in: child)
    }

    /// `node` with the value at `path` replaced, or removed when `new` is nil (an array element is taken out).
    private static func set(_ node: Any, at path: ArraySlice<any CodingKey>, to new: Any?) -> Any {
        guard let key = path.first else { return new ?? NSNull() }
        let rest = path.dropFirst()
        if var array = node as? [Any], let i = key.intValue, array.indices.contains(i) {
            if rest.isEmpty, new == nil { array.remove(at: i) } else { array[i] = set(array[i], at: rest, to: new) }
            return array
        }
        guard var object = node as? [String: Any] else { return node }
        if rest.isEmpty {
            object[key.stringValue] = new
        } else if let child = object[key.stringValue] {
            object[key.stringValue] = set(child, at: rest, to: new)
        }
        return object
    }
}
