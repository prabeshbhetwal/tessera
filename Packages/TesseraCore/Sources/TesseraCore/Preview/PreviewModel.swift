import CoreGraphics

/// Everything the preview needs for one selection. All rects are AppKit global coordinates.
public struct PreviewInput: Sendable {
    public let target: CGRect
    public let current: CGRect?
    public let neighbours: [CGRect]
    public let selection: Selection
    public let reduceMotion: Bool

    public init(target: CGRect, current: CGRect?, neighbours: [CGRect], selection: Selection, reduceMotion: Bool) {
        self.target = target
        self.current = current
        self.neighbours = neighbours
        self.selection = selection
        self.reduceMotion = reduceMotion
    }
}

/// What the overlay should draw. A layer that is switched off is nil, empty or false.
public struct PreviewLayers: Equatable, Sendable {
    public let frame: CGRect
    public let label: String?
    public let dimRects: [CGRect]
    public let fromOutline: CGRect?
    public let style: PreviewStyle
    public let animate: Bool
    /// Seconds, already clamped to 0...0.4.
    public let springResponse: Double

    public init(
        frame: CGRect, label: String?, dimRects: [CGRect], fromOutline: CGRect?,
        style: PreviewStyle, animate: Bool, springResponse: Double
    ) {
        self.frame = frame
        self.label = label
        self.dimRects = dimRects
        self.fromOutline = fromOutline
        self.style = style
        self.animate = animate
        self.springResponse = springResponse
    }
}

/// Pure model behind the four preview layers (spec §4.6).
public enum PreviewModel {
    /// A neighbour is dimmed when more than this share of its own area is covered. Exclusive.
    private static let dimThreshold: CGFloat = 0.2
    private static let maxSpringResponse = 0.4
    /// Pointing sessions that show the "click to add columns" hint before the label drops it.
    public static let hintSessions = 5

    /// `hint` swaps a span's label for the "click to add columns" hint.
    public static func layers(_ input: PreviewInput, settings: PreviewSettings, hint: Bool = false) -> PreviewLayers {
        let response = settings.springResponse.isFinite
            ? min(max(settings.springResponse, 0), maxSpringResponse)
            : 0
        return PreviewLayers(
            frame: input.target,
            label: settings.showLabel ? label(for: input.selection, frame: input.target, hint: hint) : nil,
            dimRects: settings.showNeighbours ? dimmed(input.neighbours, by: input.target) : [],
            fromOutline: settings.showCurrentOutline ? input.current : nil,
            style: settings.style,
            animate: settings.morph && !input.reduceMotion && response > 0,
            springResponse: response
        )
    }

    /// `"756 × 949 · Left half"`, `"1280 × 1047 · cols 2–3 · top"`. Nil for `.none` or a non-finite frame.
    /// With `hint`, a span reads `"Col 2 · click to add columns"` instead.
    public static func label(for selection: Selection, frame: CGRect, hint: Bool = false) -> String? {
        guard frame.width.isFinite, frame.height.isFinite else { return nil }

        let slot: String
        switch selection {
        case .none:
            return nil
        case let .wedge(_, action):
            slot = action.displayName
        case let .span(_, span):
            let first = span.columns.lowerBound + 1
            let last = span.columns.upperBound + 1
            var text = first == last ? "col \(first)" : "cols \(first)\u{2013}\(last)"
            switch span.band {
            case .full: break
            case .top: text += " · top"
            case .bottom: text += " · bottom"
            }
            if hint { return text.prefix(1).uppercased() + text.dropFirst() + " · click to add columns" }
            slot = text
        }
        return "\(points(frame.width)) × \(points(frame.height)) · \(slot)"
    }

    private static func dimmed(_ neighbours: [CGRect], by target: CGRect) -> [CGRect] {
        neighbours.filter { neighbour in
            let area = neighbour.width * neighbour.height
            guard area > 0 else { return false }
            let overlap = neighbour.intersection(target)
            guard !overlap.isNull else { return false }
            return overlap.width * overlap.height / area > dimThreshold
        }
    }

    /// Rounded whole points; clamped so absurd frames cannot trap in `Int(_:)`.
    private static func points(_ value: CGFloat) -> Int {
        Int(min(max(value, -1e9), 1e9).rounded())
    }
}
