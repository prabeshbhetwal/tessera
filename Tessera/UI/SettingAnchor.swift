import SwiftUI

extension EnvironmentValues {
    /// Key of the pane being shown (`SettingsPane` case name), so anchors build the same ids as the catalog.
    @Entry var settingsPaneKey = ""
    /// Id of the row a search result just revealed; that row draws a highlight until it is cleared.
    @Entry var settingsHighlight: String?
}

extension View {
    /// Tags a settings row so a search result can scroll to it and highlight it. `anchor` must match the
    /// entry's anchor in `SettingsCatalog` (a core test checks every catalog anchor is tagged here).
    /// A nil anchor leaves the view as it is.
    @ViewBuilder func settingAnchor(_ anchor: String?) -> some View {
        if let anchor { modifier(SettingAnchor(anchor: anchor)) } else { self }
    }
}

private struct SettingAnchor: ViewModifier {
    let anchor: String
    @Environment(\.settingsPaneKey) private var pane
    @Environment(\.settingsHighlight) private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let id = "\(pane)/\(anchor)"
        let lit = highlight == id
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        content
            .id(id)
            .background {
                shape.fill(Color.accentColor.opacity(lit ? 0.14 : 0))
                    .overlay(shape.strokeBorder(Color.accentColor.opacity(lit ? 0.85 : 0), lineWidth: 2))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: lit)
    }
}
