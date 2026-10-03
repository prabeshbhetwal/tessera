import Foundation

public enum CommandParseError: Error, Equatable, LocalizedError {
    /// The message names the offending part of the input.
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// Turns `tessera://` URLs and CLI argv into `Command`s (M2 spec §2). Both go through one builder, so the two
/// syntaxes cannot drift apart. Parsing is strict: anything unrecognised is an error and nothing is guessed.
public enum CommandParser {
    public static let usage = """
        usage:
          tessera apply --cols <2 | 2-4 | 2..4 | -1 | -2..-1> [--band full|top|bottom] [--display current|cursor|N|id:KEY]
          tessera action <name> [--display D]      (maximize, center, leftHalf, rightHalf, topHalf, bottomHalf,
                                                    topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter)
          tessera cycle <name>
          tessera columns (--set N | --delta N) [--display D]
          tessera move <next|previous|N>
          tessera undo
          tessera displays [--json]
          tessera window [--json]
          tessera settings open
          tessera settings export <path>
          tessera settings import <path>
        Use `..` for ranges that involve a negative column. Negative columns count from the right (-1 is the last).
        """

    private static let verbs = "apply, action, cycle, columns, move, undo, displays, window, settings"

    // MARK: Entry points

    public static func parse(url: URL) throws -> Command {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw invalid("unreadable URL '\(url.absoluteString)'")
        }
        guard c.scheme?.lowercased() == "tessera" else {
            throw invalid("unsupported URL scheme '\(c.scheme ?? "")', expected tessera")
        }
        var segments = (c.host.flatMap { $0.isEmpty ? nil : [$0] } ?? []) + c.path.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { throw invalid("missing command in URL (expected one of: \(verbs))") }
        let verb = segments.removeFirst().lowercased()

        // A web page can open any URL, so URLs may not read or write files or query state.
        let sub = segments.first?.lowercased() ?? ""
        if ["displays", "window"].contains(verb) || (verb == "settings" && ["export", "import"].contains(sub)) {
            throw invalid("'\(([verb] + (verb == "settings" ? [sub] : [])).joined(separator: " "))' is not available via URL")
        }

        var options: [String: String] = [:]
        for item in c.queryItems ?? [] {
            guard options[item.name] == nil else { throw invalid("duplicate parameter '\(item.name)'") }
            options[item.name] = item.value ?? ""
        }
        return try build(verb: verb, positional: segments, options: options, prefix: "")
    }

    /// `arguments` is argv without the program name. A bare `--json` is accepted anywhere and ignored (the CLI
    /// reads it itself).
    public static func parse(arguments: [String]) throws -> Command {
        var positional: [String] = []
        var options: [String: String] = [:]
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            i += 1
            if arg == "--json" { continue }
            guard arg.hasPrefix("--"), arg.count > 2 else { positional.append(arg); continue }
            let body = arg.dropFirst(2)
            let name: String, value: String
            if let eq = body.firstIndex(of: "=") {
                name = String(body[..<eq])
                value = String(body[body.index(after: eq)...])
            } else {
                name = String(body)
                // Negative numbers start with a single "-", so they are values; another "--flag" is not.
                guard i < arguments.count, !arguments[i].hasPrefix("--") else { throw invalid("missing value for --\(name)") }
                value = arguments[i]
                i += 1
            }
            guard options[name] == nil else { throw invalid("duplicate option --\(name)") }
            options[name] = value
        }
        guard !positional.isEmpty else { throw invalid("no command given (expected one of: \(verbs))") }
        let verb = positional.removeFirst().lowercased()
        return try build(verb: verb, positional: positional, options: options, prefix: "--")
    }

    // MARK: Builder

    private static func invalid(_ message: String) -> CommandParseError { .invalid(message) }

    /// `prefix` is how options are spelled in messages: "--" for the CLI, "" for URLs.
    private static func build(verb: String, positional: [String], options: [String: String], prefix: String) throws -> Command {
        var pos = positional
        var opts = options

        func value(_ key: String) throws -> String? {
            guard let v = opts.removeValue(forKey: key) else { return nil }
            guard !v.isEmpty else { throw invalid("missing value for '\(prefix)\(key)'") }
            return v
        }
        func firstPositional() -> String? { pos.isEmpty ? nil : pos.removeFirst() }
        func finish() throws {
            if let key = opts.keys.sorted().first { throw invalid("unknown option '\(prefix)\(key)' for \(verb)") }
            if let extra = pos.first { throw invalid("unexpected argument '\(extra)' for \(verb)") }
        }
        func display() throws -> DisplaySelector { try value("display").map(parseDisplay) ?? .current }

        switch verb {
        case "apply":
            guard let cols = try value("cols") else {
                throw invalid("apply needs '\(prefix)cols' (for example 2-4 or -2..-1)")
            }
            let range = try parseColumns(cols)
            let band = try value("band").map(parseBand) ?? .full
            let selector = try display()
            try finish()
            return .apply(.span(columns: range, band: band), display: selector)

        case "action":
            guard let name = firstPositional() else { throw invalid("action needs a window action name, for example leftHalf") }
            guard let action = WindowAction.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else {
                throw invalid("unknown action '\(name)' (expected one of: \(WindowAction.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            let selector = try display()
            try finish()
            return .apply(.action(action), display: selector)

        case "cycle":
            guard let name = firstPositional() else { throw invalid("cycle needs a cycle name, for example left") }
            try finish()
            return .cycle(name: name)

        case "columns":
            let set = try value("set"), delta = try value("delta")
            let selector = try display()
            try finish()
            switch (set, delta) {
            case (nil, nil): throw invalid("columns needs '\(prefix)set' or '\(prefix)delta'")
            case (.some, .some): throw invalid("columns takes '\(prefix)set' or '\(prefix)delta', not both")
            case (let s?, nil): return .columns(.set(try parseInt(s, what: "\(prefix)set")), display: selector)
            case (nil, let d?): return .columns(.delta(try parseInt(d, what: "\(prefix)delta")), display: selector)
            }

        case "move":
            let positionalTarget = firstPositional(), optionTarget = try value("display")
            try finish()
            if positionalTarget != nil, optionTarget != nil { throw invalid("move takes the display once, not twice") }
            guard let target = positionalTarget ?? optionTarget else { throw invalid("move needs next, previous or a display number") }
            return .moveToDisplay(try parseStep(target))

        case "undo":
            try finish()
            return .undo

        case "displays":
            try finish()
            return .listDisplays

        case "window":
            try finish()
            return .describeWindow

        case "settings":
            guard let sub = firstPositional() else { throw invalid("settings needs open, export or import") }
            switch sub.lowercased() {
            case "open":
                try finish()
                return .openSettings
            case "export", "import":
                guard let path = firstPositional(), !path.isEmpty else { throw invalid("settings \(sub) needs a file path") }
                try finish()
                return sub.lowercased() == "export" ? .exportSettings(path: path) : .importSettings(path: path)
            default:
                throw invalid("unknown settings subcommand '\(sub)' (expected open, export or import)")
            }

        default:
            throw invalid("unknown command '\(verb)' (expected one of: \(verbs))")
        }
    }

    // MARK: Values

    private static func parseInt(_ text: String, what: String) throws -> Int {
        guard let v = Int(text) else { throw invalid("\(what) '\(text)' is not a whole number") }
        return v
    }

    /// `2`, `2-4`, `2..4`, `-1`, `-2..-1`. A `..` always splits; otherwise a dash after the first character does.
    /// Ranges must run low to high, so a range mixing positive and negative columns (`2..-1`) cannot be expressed.
    private static func parseColumns(_ text: String) throws -> ClosedRange<Int> {
        func number(_ s: Substring) throws -> Int {
            guard let v = Int(s) else { throw invalid("columns '\(text)': '\(s)' is not a whole number") }
            return v
        }
        let lo: Int, hi: Int
        if let r = text.range(of: "..") {
            lo = try number(text[..<r.lowerBound])
            hi = try number(text[r.upperBound...])
        } else if let dash = text.dropFirst().firstIndex(of: "-") {
            lo = try number(text[..<dash])
            hi = try number(text[text.index(after: dash)...])
        } else {
            lo = try number(text[...])
            hi = lo
        }
        guard lo <= hi else {
            let mixed = (lo > 0) != (hi > 0) && lo != 0 && hi != 0
            throw invalid("columns '\(text)': start is after end"
                + (mixed ? " (ranges mixing positive and negative columns are not supported)" : ""))
        }
        return lo...hi
    }

    private static func parseBand(_ text: String) throws -> Band {
        guard let band = Band(rawValue: text.lowercased()) else {
            throw invalid("band '\(text)': expected full, top or bottom")
        }
        return band
    }

    private static func parseDisplay(_ text: String) throws -> DisplaySelector {
        switch text.lowercased() {
        case "current": return .current
        case "cursor": return .cursor
        case let t where t.hasPrefix("id:"):
            let key = String(text.dropFirst(3))
            guard !key.isEmpty else { throw invalid("display '\(text)': id: needs a display key") }
            return .id(key)
        default:
            guard let n = Int(text) else {
                throw invalid("display '\(text)': expected current, cursor, a number or id:<key>")
            }
            guard n >= 1 else { throw invalid("display '\(text)': display numbers start at 1") }
            return .index(n)
        }
    }

    private static func parseStep(_ text: String) throws -> DisplayStep {
        switch text.lowercased() {
        case "next": return .next
        case "previous": return .previous
        default:
            guard let n = Int(text), n >= 1 else {
                throw invalid("display '\(text)': expected next, previous or a display number starting at 1")
            }
            return .index(n)
        }
    }
}
