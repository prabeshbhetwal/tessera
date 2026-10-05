/// Pure operations on the list of remembered splits. Order is oldest first, newest last.
public enum SplitMemory {
    public static let capacity = 50

    public static func lookup(_ key: SplitKey, in splits: [LearnedSplit]) -> LearnedSplit? {
        splits.first { $0.key == key }
    }

    /// Replaces any entry with the same key, appends `split` as the newest, and drops the oldest beyond `capacity`.
    public static func upsert(_ split: LearnedSplit, into splits: [LearnedSplit]) -> [LearnedSplit] {
        Array((forget(split.key, in: splits) + [split]).suffix(capacity))
    }

    public static func forget(_ key: SplitKey, in splits: [LearnedSplit]) -> [LearnedSplit] {
        splits.filter { $0.key != key }
    }
}
