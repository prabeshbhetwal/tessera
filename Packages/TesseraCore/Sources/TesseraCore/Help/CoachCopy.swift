import CoreGraphics
import Foundation

/// Small wording helpers for the coach. Plain Australian English.
public enum CoachCopy {
    /// "A", "A and B", "A, B and C".
    public static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    private static let named: [(value: Double, word: String)] = [
        (1.0 / 4, "a quarter"), (1.0 / 3, "a third"), (1.0 / 2, "half"),
        (2.0 / 3, "two thirds"), (3.0 / 4, "three quarters"),
    ]

    /// The nearest named fraction within 0.03, otherwise a percentage.
    public static func share(_ fraction: Double) -> String {
        if let hit = named.min(by: { abs($0.value - fraction) < abs($1.value - fraction) }),
           abs(hit.value - fraction) <= 0.03 {
            return hit.word
        }
        return "\(Int((fraction * 100).rounded()))%"
    }

    public static func equalShare(_ count: Int) -> String {
        switch count {
        case 2: "half"
        case 3: "a third"
        case 4: "a quarter"
        case 5: "a fifth"
        case 6: "a sixth"
        default: "an equal share"
        }
    }

    /// "Dia half, the others a quarter each", or "Dia half, Claude a third, Codex 17%".
    /// Frames are in on-screen order; the axis is width, or height on a portrait display.
    public static func shares(apps: [String], frames: [CGRect], usable: CGRect, portrait: Bool) -> String {
        let total = portrait ? usable.height : usable.width
        guard total > 0, apps.count == frames.count else { return list(apps) }
        let words = frames.map { share((portrait ? $0.height : $0.width) / total) }
        if words.count >= 3, words.dropFirst().allSatisfy({ $0 == words[1] }) {
            return "\(apps[0]) \(words[0]), the others \(words[1]) each"
        }
        return zip(apps, words).map { "\($0) \($1)" }.joined(separator: ", ")
    }

    /// "7 Nov", in the current time zone unless given another.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM"
        var text = formatter.string(from: date)
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
