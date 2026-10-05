import CoreGraphics
import Foundation

/// A rectangle as fractions of a usable frame. AppKit orientation: `y` is measured from the bottom.
public struct UnitRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Expresses `rect` as fractions of `usable`. A degenerate `usable` yields zeros rather than NaN/inf,
    /// which `JSONEncoder` would refuse to persist.
    public init(_ rect: CGRect, in usable: CGRect) {
        guard usable.width > 0, usable.height > 0 else {
            self.init(x: 0, y: 0, width: 0, height: 0)
            return
        }
        self.init(
            x: (rect.minX - usable.minX) / usable.width,
            y: (rect.minY - usable.minY) / usable.height,
            width: rect.width / usable.width,
            height: rect.height / usable.height
        )
    }

    public func absolute(in usable: CGRect) -> CGRect {
        CGRect(
            x: usable.minX + x * usable.width,
            y: usable.minY + y * usable.height,
            width: width * usable.width,
            height: height * usable.height
        )
    }
}

/// One app's remembered place within a split.
public struct Slot: Codable, Equatable, Sendable {
    public var bundleID: String
    public var rect: UnitRect

    public init(bundleID: String, rect: UnitRect) {
        self.bundleID = bundleID
        self.rect = rect
    }
}

/// Identifies an arrangement: a display plus the multiset of apps in it. App order never matters.
public struct SplitKey: Codable, Hashable, Sendable {
    public let display: String
    public let apps: [String]

    /// `apps` is stored sorted with repeats kept; a window without a bundle ID becomes `"?"`.
    public init(display: String, bundleIDs: [String?]) {
        self.display = display
        self.apps = bundleIDs.map { $0 ?? "?" }.sorted()
    }

    /// Re-runs the sorting init so a hand-edited or unsorted payload still equals a freshly built key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            display: try container.decode(String.self, forKey: .display),
            bundleIDs: try container.decode([String].self, forKey: .apps)
        )
    }
}

public struct LearnedSplit: Codable, Equatable, Sendable {
    public var key: SplitKey
    public var slots: [Slot]
    public var updated: Date

    public init(key: SplitKey, slots: [Slot], updated: Date) {
        self.key = key
        self.slots = slots
        self.updated = updated
    }
}

/// Whether a learned gap keeps its sequence index or travels with the slot it followed
/// when windows are applied in a different order from the one learned.
public enum SplitGapPlacement: String, Codable, CaseIterable, Equatable, Sendable {
    case staysInPlace, followsNeighbour
}

/// How a gap behaves when a neighbouring slot grows.
public enum SplitGapWhenGrowing: String, Codable, CaseIterable, Equatable, Sendable {
    case fixed, shrinks
}
