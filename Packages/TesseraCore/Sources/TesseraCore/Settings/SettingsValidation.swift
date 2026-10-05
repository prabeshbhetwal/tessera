public enum SettingsError: Error, Equatable, Sendable {
    /// The associated text names the first problem found and is safe to show to the user.
    case invalid(String)
}

/// Structural checks applied to loaded, saved, exported and imported settings (plan C2).
/// Conditions are written in the positive form so NaN fails them.
public enum SettingsValidation {
    /// Highest schema this build can read. A higher version is rejected, never half-read.
    public static let currentSchemaVersion = 2

    public static func validate(_ s: TesseraSettings) throws {
        func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            if !condition { throw SettingsError.invalid(message()) }
        }
        func nonNegative(_ value: Double, _ what: String) throws {
            try require(value >= 0 && value.isFinite, "\(what) can't be negative (found \(value)).")
        }
        func fraction(_ value: Double, _ what: String) throws {
            try require(value >= 0 && value <= 1, "\(what) must be between 0 and 1 (found \(value)).")
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
        try require(c.maxColumnWidth.isFinite && c.minRowHeight > 0 && c.minRowHeight.isFinite,
                    "Column widths and the row height must be finite and positive.")
        try require(
            (1...16).contains(c.maxColumns),
            "Maximum columns must be between 1 and 16 (found \(c.maxColumns))."
        )

        try nonNegative(s.defaultGap, "The default gap")
        try nonNegative(s.defaultPadding, "The default padding")

        let r = s.ring
        try require(
            r.deadZone >= 0 && r.deadZone < r.flickDistance && r.flickDistance.isFinite,
            "Dead zone must be at least 0 and smaller than the flick distance."
        )
        try require(r.topBand >= 0 && r.bottomBand >= 0 && r.topBand + r.bottomBand < 1,
                    "Top and bottom bands must each be at least 0 and add up to less than 100%.")
        try require(r.radius > 0 && r.radius.isFinite && r.thickness > 0 && r.thickness.isFinite,
                    "Ring radius and thickness must be positive.")

        let p = s.preview
        try fraction(p.opacity, "Preview fill opacity")
        try fraction(p.dimStrength, "Neighbour dim strength")
        try nonNegative(p.borderWidth, "Preview border width")
        try nonNegative(p.cornerRadius, "Preview corner radius")
        try nonNegative(p.springResponse, "Preview spring response")

        try require(s.hudSeconds >= 0.3 && s.hudSeconds <= 10, "Messages must stay between 0.3 and 10 seconds.")

        try require(
            s.snapDuration >= 0 && s.snapDuration <= SnapSpeed.maxSeconds,
            "Snap duration must be between 0 and \(SnapSpeed.maxSeconds) seconds."
        )

        // Only corrupt numbers and the cap are rejected. A split whose slots don't match its key, or whose
        // slots overlap, is harmless: the applier returns nil for it at Tile time, and rejecting it here
        // would quarantine the user's whole settings file.
        try require(s.learnedSplits.count <= SplitMemory.capacity,
                    "Too many learned splits (at most \(SplitMemory.capacity)).")
        for split in s.learnedSplits {
            for r in split.slots.map(\.rect) {
                try require(
                    r.x.isFinite && r.y.isFinite && r.width.isFinite && r.height.isFinite
                        && r.width > 0 && r.height > 0 && r.x >= 0 && r.y >= 0
                        && r.x + r.width <= 1.0001 && r.y + r.height <= 1.0001,
                    "A learned split has an invalid size."
                )
            }
        }

        for key in s.displayOverrides.keys.sorted() {
            let profile = s.displayOverrides[key] ?? DisplayProfile(columns: 0)
            try require(profile.columns >= 1, "Display \(key) needs at least 1 column (found \(profile.columns)).")
            try nonNegative(profile.gap, "Display \(key)'s gap")
            try nonNegative(profile.padding, "Display \(key)'s padding")
        }

        for theme in s.customThemes {
            try require(!theme.name.isEmpty, "Every custom theme needs a name.")
            try fraction(theme.ring.opacity, "Theme \(theme.name)'s ring opacity")
        }

        let ids = s.hotkeys.map(\.id)
        try require(Set(ids).count == ids.count, "Two hotkeys share the same id; each needs its own.")

        try require(!s.trigger.keyCodes.isEmpty, "The trigger chord needs at least one key.")
    }
}
