import Foundation

/// One searchable setting: where it lives and the words people might use for it.
public struct SettingsEntry: Sendable, Hashable, Identifiable {
    /// Settings pane key, the app's `SettingsPane` case name (`"displays"`).
    public let pane: String
    /// Section heading the setting sits under, shown in the result's breadcrumb.
    public let section: String
    /// The row's label as the user sees it.
    public let title: String
    /// Other words for it: what someone looking for this setting might type.
    public let keywords: [String]
    /// The literal the app tags the row with to scroll to and highlight it; nil only opens the pane.
    public let anchor: String?

    public init(_ pane: String, _ section: String, _ title: String, anchor: String? = "", _ keywords: [String] = []) {
        self.pane = pane
        self.section = section
        self.title = title
        self.keywords = keywords
        self.anchor = anchor == "" ? title : anchor
    }

    public var id: String { "\(pane)/\(anchor ?? title)" }
}

/// Forgiving local search over `SettingsCatalog`: ignores filler words ("how do I remove the…"), treats
/// synonyms as the same word (spacing, gap, gutter), tolerates typos, and matches words still being typed.
public enum SettingsSearch {
    /// Best matches first; empty for an empty query or when nothing is close enough.
    public static func results(for query: String, limit: Int = 12) -> [SettingsEntry] {
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        let meaningful = words.filter { !stopwords.contains($0) }
        let terms = meaningful.isEmpty ? words : meaningful
        let phrase = normalise(query)
        return index.enumerated()
            .compactMap { position, item -> (Double, Int, SettingsEntry)? in
                let s = score(terms, phrase: phrase, item: item)
                return s >= threshold(terms.count) ? (s, position, item.entry) : nil
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .prefix(limit)
            .map(\.2)
    }

    /// An entry with its words worked out once, so each keystroke only compares.
    private struct Indexed: Sendable {
        let entry: SettingsEntry
        let title: [String]
        let normalisedTitle: String
        let keywordPhrases: [String]
        let fields: [(words: [String], weight: Double)]

        init(_ entry: SettingsEntry) {
            self.entry = entry
            title = SettingsSearch.tokens(entry.title)
            normalisedTitle = SettingsSearch.normalise(entry.title)
            let keywords = entry.keywords.map(SettingsSearch.tokens)
            keywordPhrases = keywords.map { " \($0.joined(separator: " ")) " }
            fields = [
                (title, 1),
                (keywords.flatMap { $0 }, 0.95),
                (SettingsSearch.tokens(entry.section), 0.7),
                (SettingsSearch.tokens(entry.pane.splitCamelCase), 0.6),
            ]
        }
    }

    private static let index = SettingsCatalog.entries.map(Indexed.init)

    /// One word needs a strong match; longer queries can carry a word that matches nothing.
    private static func threshold(_ count: Int) -> Double { count == 1 ? 0.7 : 0.5 }

    private static func score(_ terms: [String], phrase: String, item: Indexed) -> Double {
        let title = item.title, fields = item.fields
        var total = 0.0, inTitle = 0
        for term in terms {
            let best = fields.map { field in (field.words.map { match(term, $0) }.max() ?? 0) * field.weight }.max() ?? 0
            total += best
            if title.contains(where: { match(term, $0) >= 0.8 }) { inTitle += 1 }
        }
        let titleCovered = title.filter { word in terms.contains { match($0, word) >= 0.8 } }.count
        var result = total / Double(terms.count) + 0.1 * Double(inTitle) / Double(terms.count)
            + 0.05 * Double(titleCovered) / Double(max(title.count, 1))
        // The words typed, in order, inside the title or one of the keyword phrases.
        let wanted = " \(terms.joined(separator: " ")) "
        if phrase.count >= 3, item.normalisedTitle.contains(phrase) { result += 0.3 }
        else if terms.count >= 2, item.keywordPhrases.contains(where: { $0.contains(wanted) }) {
            result += 0.2
        }
        return result
    }

    /// How well a typed word matches a word of the entry, 0…1.
    static func match(_ typed: String, _ word: String) -> Double {
        if typed == word { return 1 }
        let a = canonical(typed), b = canonical(word)
        if a == b { return 0.92 }
        // Still typing: "pad" for padding. Two letters only count as the start of a word.
        if typed.count >= 2, word.hasPrefix(typed) { return typed.count >= 3 ? 0.85 : 0.7 }
        if word.count >= 4, typed.hasPrefix(word) { return 0.8 }
        let allowed = typed.count >= 8 ? 2 : typed.count >= 4 ? 1 : 0
        if allowed > 0, abs(typed.count - word.count) <= allowed,
           distance(typed, word) <= allowed || distance(a, b) <= allowed { return 0.75 }
        // Three letters forgive only swapped letters ("gpa"), or every short word would match.
        if typed.count == 3, word.count == 3, typed.sorted() == word.sorted(), distance(typed, word) == 1 { return 0.75 }
        return 0
    }

    /// Lowercase words without accents or punctuation, with a plain plural "s" removed.
    static func tokens(_ text: String) -> [String] {
        normalise(text).split(separator: " ").map { singular(String($0)) }
    }

    static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        let cleaned = folded.unicodeScalars.map { letters.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    private static let locale = Locale(identifier: "en_AU")
    private static let letters = CharacterSet.alphanumerics

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"),
              !["ss", "us", "is"].contains(where: word.hasSuffix) else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        return String(word.dropLast())
    }

    private static func canonical(_ word: String) -> String { synonymIndex[word] ?? word }

    /// Optimal string alignment distance: insertions, deletions, substitutions and adjacent swaps.
    static func distance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty || t.isEmpty { return max(s.count, t.count) }
        // Three rolling rows: the one before last is needed for adjacent swaps.
        var older = [Int](repeating: 0, count: t.count + 1)
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] { current[j] = min(current[j], older[j - 2] + 1) }
            }
            (older, previous, current) = (previous, current, older)
        }
        return previous[t.count]
    }

    /// Words that ask for something rather than name it: "how do I turn off the…". Singular forms.
    static let stopwords: Set<String> = [
        "a", "an", "the", "to", "of", "for", "in", "on", "at", "by", "with", "and", "or", "from", "into",
        "i", "me", "my", "we", "you", "your", "it", "its", "is", "are", "be", "can", "could", "would",
        "should", "how", "do", "doe", "did", "where", "what", "which", "why", "want", "need", "wanna", "please",
        "make", "set", "change", "adjust", "turn", "get", "remove", "delete", "add", "put", "use", "using",
        "setting", "option", "preference", "there", "no", "not", "off", "enable", "enabled", "disable",
        "disabled", "show", "hide", "toggle", "stop", "all", "more", "less", "any", "some", "so", "that", "this",
        "find", "when", "let", "just", "too", "very", "way", "tessera", "one", "thing",
    ]

    /// Each group's first word stands for the whole group. Singular forms, as `tokens` produces them.
    static let synonyms: [[String]] = [
        ["gap", "spacing", "space", "gutter", "between", "spaced", "apart"],
        ["padding", "margin", "inset", "edge", "border"],
        ["window", "frame"],
        ["app", "application", "program"],
        ["display", "monitor", "screen"],
        ["colour", "color", "hue", "palette"],
        ["centre", "center", "middle"],
        ["grey", "gray"],
        ["behaviour", "behavior"],
        ["shortcut", "hotkey", "keybinding", "keybind", "binding", "keystroke"],
        ["column", "col", "row"],
        ["tile", "tiled", "tiling", "tiler"],
        ["snap", "snapping", "snapped", "move", "moving", "place", "placement"],
        ["speed", "fast", "faster", "slow", "slower", "quick", "quicker", "duration", "instant"],
        ["animation", "animate", "animated", "motion", "glide", "transition", "spring"],
        ["launch", "startup", "login", "boot", "autostart", "autolaunch", "logon"],
        ["update", "upgrade", "sparkle", "version", "release"],
        ["opacity", "transparency", "transparent", "opaque", "translucent", "alpha"],
        ["size", "bigger", "smaller", "large", "larger", "small", "big", "scale"],
        ["exclude", "excluded", "ignore", "ignored", "blacklist", "blocklist", "except", "exception"],
        ["reset", "default", "restore", "factory"],
        ["appearance", "dark", "light", "theme"],
        ["learn", "learned", "learnt", "remember", "memory", "split"],
        ["tip", "hint", "help", "guide", "tutorial"],
        ["message", "hud", "notification", "toast", "banner", "popup"],
        ["dim", "dimming", "darken", "shade", "shadow"],
        ["label", "caption", "text", "name"],
        ["export", "backup", "save"],
        ["import", "load"],
        ["cli", "terminal", "command"],
        ["menu", "menubar", "statusbar", "tray"],
        ["preview", "ghost", "outline"],
        ["voiceover", "accessibility", "announce", "screenreader"],
    ]

    private static let synonymIndex: [String: String] = {
        var index: [String: String] = [:]
        for group in synonyms { for word in group { index[word] = index[word] ?? group[0] } }
        return index
    }()
}

private extension String {
    /// "excludedApps" → "excluded Apps", so a pane key reads as words.
    var splitCamelCase: String {
        reduce(into: "") { out, c in if c.isUppercase, !out.isEmpty { out.append(" ") }; out.append(c) }
    }
}
