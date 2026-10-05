/// Visible feedback independent of the optional size/slot label on the window preview.
public struct RingFeedback: Equatable, Sendable {
    public let title: String
    public let hint: String

    public static func make(selection: Selection, ring: RingSettings, keyboard: Bool,
                            keyboardEnabled: Bool, tapToTile: Bool, cancelling: Bool) -> RingFeedback {
        let apply = keyboard ? "↵ Apply · esc Cancel" : "Release to snap"
        switch selection {
        case let .wedge(_, action):
            return RingFeedback(title: action.displayName, hint: apply)
        case let .span(_, span):
            let lo = span.columns.lowerBound + 1, hi = span.columns.upperBound + 1
            let columns = lo == hi ? "Column \(lo)" : "Columns \(lo)–\(hi)"
            let band = switch span.band { case .full: ""; case .top: " · top"; case .bottom: " · bottom" }
            return RingFeedback(title: columns + band, hint: apply)
        case .none:
            if tapToTile {
                return RingFeedback(title: "Release to tile all windows", hint: "Move to choose · esc Cancel")
            }
            let hint: String
            if ring.directions && ring.pointing { hint = "Flick or point" }
            else if ring.directions { hint = "Flick to choose" }
            else if ring.pointing { hint = "Point at a column" }
            else if keyboardEnabled { hint = "← → Select · esc Cancel" }
            else { hint = "Enable a gesture in Settings → Ring" }
            return RingFeedback(title: cancelling ? "Release here to cancel" : "Choose a layout", hint: hint)
        }
    }
}
