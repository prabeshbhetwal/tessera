import Foundation

extension SettingsValidation {
    /// Fixes every value `validate` would reject where the fix is obvious, and says what it changed, one sentence
    /// each. Load and import run it before `validate`, so one out-of-range number no longer sets the whole file
    /// aside; save and export stay strict. Valid settings come back unchanged with no repairs. `schemaVersion` is
    /// never touched: a version this build can't read is the caller's decision.
    public static func repair(_ input: TesseraSettings) -> (settings: TesseraSettings, repairs: [String]) {
        var s = input
        var repairs: [String] = []
        let d = TesseraSettings.defaults

        /// Out of range moves to the nearest end; NaN or infinity takes `fallback`.
        func clamp(_ value: inout Double, _ range: ClosedRange<Double>, _ fallback: Double, _ what: String) {
            guard !(range.contains(value) && value.isFinite) else { return }
            let old = value
            value = value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
            repairs.append("\(what) was \(format(old)) and is now \(format(value)).")
        }
        func clamp(_ value: inout Int, _ range: ClosedRange<Int>, _ what: String) {
            guard !range.contains(value) else { return }
            let old = value
            value = min(max(value, range.lowerBound), range.upperBound)
            repairs.append("\(what) was \(old) and is now \(value).")
        }
        /// Zero, negative, NaN or infinite takes `fallback`.
        func positive(_ value: inout Double, _ fallback: Double, _ what: String) {
            guard !(value > 0 && value.isFinite) else { return }
            repairs.append("\(what) was \(format(value)) and is now \(format(fallback)).")
            value = fallback
        }
        let anySize = 0...Double.greatestFiniteMagnitude

        if s.ring.wedges.count != 8 {
            repairs.append("The ring had \(s.ring.wedges.count) directions; they are back to the default eight.")
            s.ring.wedges = d.ring.wedges
        }

        positive(&s.sizing.minColumnWidth, d.sizing.minColumnWidth, "The minimum column width")
        positive(&s.sizing.idealColumnWidth, d.sizing.idealColumnWidth, "The ideal column width")
        positive(&s.sizing.maxColumnWidth, d.sizing.maxColumnWidth, "The maximum column width")
        positive(&s.sizing.minRowHeight, d.sizing.minRowHeight, "The minimum row height")
        let widths = [s.sizing.minColumnWidth, s.sizing.idealColumnWidth, s.sizing.maxColumnWidth]
        if widths != widths.sorted() {
            let sorted = widths.sorted()
            (s.sizing.minColumnWidth, s.sizing.idealColumnWidth, s.sizing.maxColumnWidth) = (sorted[0], sorted[1], sorted[2])
            repairs.append("The minimum, ideal and maximum column widths were out of order and have been sorted.")
        }
        clamp(&s.sizing.maxColumns, 1...maxColumns, "The column limit")

        clamp(&s.defaultGap, 0...maxSpacing, d.defaultGap, "The default gap")
        clamp(&s.defaultPadding, 0...maxSpacing, d.defaultPadding, "The default padding")

        positive(&s.ring.flickDistance, d.ring.flickDistance, "The point threshold")
        positive(&s.ring.radius, d.ring.radius, "The ring radius")
        positive(&s.ring.thickness, d.ring.thickness, "The ring thickness")
        if !directionsReachable(s.ring) {
            let old = s.ring.flickDistance
            s.ring.flickDistance = max(s.ring.outerRadius, s.ring.cancelRadius + 1).rounded(.up)
            repairs.append("The point threshold was \(format(old)), inside the ring, and is now \(format(s.ring.flickDistance)).")
        }
        if !(s.ring.deadZone >= 0 && s.ring.deadZone < s.ring.flickDistance) {
            // Unused since the ring's middle became the cancel area; only its shape is kept.
            s.ring.deadZone = min(d.ring.deadZone, s.ring.flickDistance / 2)
        }
        if !(s.ring.topBand >= 0 && s.ring.bottomBand >= 0 && s.ring.topBand + s.ring.bottomBand < 1) {
            repairs.append("The top and bottom bands didn’t fit together and are back to their defaults.")
            (s.ring.topBand, s.ring.bottomBand) = (d.ring.topBand, d.ring.bottomBand)
        }

        clamp(&s.preview.opacity, 0...1, d.preview.opacity, "The preview fill opacity")
        clamp(&s.preview.dimStrength, 0...1, d.preview.dimStrength, "The neighbour dim strength")
        clamp(&s.preview.borderWidth, anySize, d.preview.borderWidth, "The preview border width")
        clamp(&s.preview.cornerRadius, anySize, d.preview.cornerRadius, "The preview corner radius")
        clamp(&s.preview.springResponse, anySize, d.preview.springResponse, "The preview spring response")
        clamp(&s.hudSeconds, 0.3...10, d.hudSeconds, "The message duration")
        clamp(&s.snapDuration, 0...SnapSpeed.maxSeconds, d.snapDuration, "The snap duration")

        let usable = s.learnedSplits.filter { $0.slots.allSatisfy { isUsable($0.rect) } }
        if usable.count < s.learnedSplits.count {
            repairs.append(count(s.learnedSplits.count - usable.count, "learned split") + " with an invalid size removed.")
            s.learnedSplits = usable
        }
        if s.learnedSplits.count > SplitMemory.capacity {
            let extra = s.learnedSplits.count - SplitMemory.capacity
            s.learnedSplits.removeFirst(extra)
            repairs.append(count(extra, "oldest learned split") + " removed to stay within \(SplitMemory.capacity).")
        }

        for key in s.displayOverrides.keys.sorted() {
            guard var p = s.displayOverrides[key] else { continue }
            clamp(&p.columns, 1...maxColumns, "Display \(key)’s columns")
            clamp(&p.gap, 0...maxSpacing, d.defaultGap, "Display \(key)’s gap")
            clamp(&p.padding, 0...maxSpacing, d.defaultPadding, "Display \(key)’s padding")
            s.displayOverrides[key] = p
        }

        for i in s.customThemes.indices {
            if s.customThemes[i].name.isEmpty {
                s.customThemes[i].name = "Untitled"
                repairs.append("A custom theme with no name is now called Untitled.")
            }
            clamp(&s.customThemes[i].ring.opacity, 0...1, Theme.default.ring.opacity,
                  "Theme \(s.customThemes[i].name)’s ring opacity")
        }

        var seen = Set<String>()
        let unique = s.hotkeys.filter { seen.insert($0.id).inserted }
        if unique.count < s.hotkeys.count {
            repairs.append(count(s.hotkeys.count - unique.count, "hotkey") + " sharing another’s id removed.")
            s.hotkeys = unique
        }

        if s.trigger.keyCodes.isEmpty {
            s.trigger = d.trigger
            repairs.append("The trigger had no keys and is back to its default.")
        }
        return (s, repairs)
    }

    private static func format(_ value: Double) -> String { String(format: "%g", value) }

    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
