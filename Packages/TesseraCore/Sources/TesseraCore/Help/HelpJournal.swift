import Foundation

/// The last few coach events, oldest first.
public struct HelpJournal: Sendable {
    public static let capacity = 10

    public private(set) var events: [HelpEvent] = []

    public init() {}

    public mutating func record(_ event: HelpEvent) {
        events.append(event)
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }

    public var latest: HelpEvent? { events.last }

    public func event(before id: UUID) -> HelpEvent? {
        guard let i = events.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
        return events[i - 1]
    }

    public func event(after id: UUID) -> HelpEvent? {
        guard let i = events.firstIndex(where: { $0.id == id }), i + 1 < events.count else { return nil }
        return events[i + 1]
    }

    /// The newest plain `.tiled` event for `key` strictly older than the event with `id`.
    public func lastTile(for key: SplitKey, before id: UUID) -> HelpEvent? {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return nil }
        return events[..<i].last { event in
            if case .tiled = event.kind { return event.key == key }
            return false
        }
    }
}
