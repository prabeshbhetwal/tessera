extension TriggerChord {
    private enum Keys: String, CodingKey { case keyCodes }

    // A chord is unordered in memory; exports must not change array order after import.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(keyCodes.sorted(), forKey: .keyCodes)
    }
}
