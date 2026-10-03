public enum SettingsError: Error, Equatable, Sendable {
    /// The associated text names the first problem found and is safe to show to the user.
    case invalid(String)
}

/// Structural checks applied to loaded, saved, exported and imported settings (plan C2).
/// Conditions are written in the positive form so NaN fails them.
public enum SettingsValidation {
    /// Highest schema this build can read. A higher version is rejected, never half-read.
    public static let currentSchemaVersion = 1

    public static func validate(_ s: TesseraSettings) throws {
        func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            if !condition { throw SettingsError.invalid(message()) }
        }

        try require(
            (1...currentSchemaVersion).contains(s.schemaVersion),
            "Settings schema version \(s.schemaVersion) is not supported (this version reads 1 to \(currentSchemaVersion))."
        )
        try require(
            s.ring.wedges.count == 8,
            "The ring needs exactly 8 wedge actions (found \(s.ring.wedges.count))."
        )

        let c = s.sizing
        try require(
            c.minColumnWidth > 0 && c.minColumnWidth <= c.idealColumnWidth && c.idealColumnWidth <= c.maxColumnWidth,
            "Column widths must satisfy 0 < minimum <= ideal <= maximum."
        )
        try require(
            (1...16).contains(c.maxColumns),
            "Maximum columns must be between 1 and 16 (found \(c.maxColumns))."
        )

        try require(
            s.ring.deadZone >= 0 && s.ring.deadZone < s.ring.flickDistance,
            "Dead zone must be at least 0 and smaller than the flick distance."
        )
        try require(
            s.ring.topBand + s.ring.bottomBand < 1,
            "Top and bottom bands must add up to less than 100%."
        )

        for key in s.displayOverrides.keys.sorted() {
            let columns = s.displayOverrides[key]?.columns ?? 0
            try require(columns >= 1, "Display \(key) needs at least 1 column (found \(columns)).")
        }

        try require(!s.trigger.keyCodes.isEmpty, "The trigger chord needs at least one key.")
    }
}
