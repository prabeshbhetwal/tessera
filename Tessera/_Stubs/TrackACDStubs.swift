// TEMPORARY STUB — coordinator deletes at merge
// Signatures copied from the milestone 1 plan (Tracks A, C, D). Bodies are placeholders.
import AppKit
import CoreGraphics
import TesseraCore

// MARK: Track A — GridKit

enum GridGeometry {
    static func usableFrame(_ visible: CGRect, profile: DisplayProfile) -> CGRect {
        visible.insetBy(dx: profile.padding, dy: profile.padding)
    }

    static func columnIndex(at x: CGFloat, in usable: CGRect, columns: Int) -> Int {
        let n = max(1, columns)
        return min(max(Int(((x - usable.minX) / (usable.width / CGFloat(n))).rounded(.down)), 0), n - 1)
    }

    static func frame(for span: ColumnSpan, display: DisplayContext) -> CGRect {
        let usable = usableFrame(display.visibleFrame, profile: display.profile)
        let w = usable.width / CGFloat(max(1, display.profile.columns))
        return CGRect(
            x: usable.minX + CGFloat(span.columns.lowerBound) * w, y: usable.minY,
            width: CGFloat(span.columns.count) * w, height: usable.height
        )
    }
}

// MARK: Track C — PreviewModel

struct PreviewLayers: Equatable, Sendable {
    var frame: CGRect
    var label: String?
    var dimRects: [CGRect]
    var fromOutline: CGRect?
    var showThumbnail: Bool
    var animate: Bool
    var springResponse: Double
}

// MARK: Track C — SettingsValidation

enum SettingsError: Error, Equatable {
    case invalid(String)
}

enum SettingsValidation {
    static func validate(_ s: TesseraSettings) throws {
        if s.ring.wedges.count != 8 { throw SettingsError.invalid("Ring must have 8 wedges") }
    }
}

// MARK: Track D — Permissions

@MainActor
enum Permissions {
    static var isAccessibilityTrusted: Bool { false }
    static func promptAccessibility() {}
    static func observeAccessibility(_ onChange: @escaping @MainActor (Bool) -> Void) -> NSObjectProtocol {
        NSObject()
    }
    static var isScreenCaptureAllowed: Bool { false }
    static func requestScreenCapture() {}
}
