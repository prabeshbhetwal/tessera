import AppKit
import SwiftUI

/// The icon-only sidebar: a narrow rail of pane icons in sidebar groups, docked to the window's leading edge.
/// Each icon is named in its tooltip and to VoiceOver. Like the full list it is one keyboard stop: clicking an icon
/// gives the rail focus (its selection turns the accent colour) and ↑ ↓ then step through the panes.
struct SettingsRail: View {
    @Bindable var navigation: SettingsNavigation
    @FocusState private var focused: Bool
    @State private var hovered: SettingsPane?
    /// The one selection plate, which glides from icon to icon.
    @Namespace private var plate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A 40 pt hit area around each 24 pt icon tile, with an even 8 pt margin either side.
    /// Wide enough that the window's close and minimise buttons, which sit over the rail, stay centred on it.
    static let width: CGFloat = 60

    private static let order = SettingsGroup.allCases.flatMap(\.panes)

    var body: some View {
        VStack(spacing: 2) {
            ForEach(SettingsGroup.allCases, id: \.self) { group in
                if group != SettingsGroup.allCases.first { Divider().frame(width: 28).padding(.vertical, 4) }
                ForEach(group.panes, id: \.self) { pane in
                    let selected = navigation.pane == pane
                    Button { navigation.pane = pane; focused = true } label: {
                        PaneIcon(pane: pane, size: 24)
                            .railCell(selection: !selected ? nil
                                      : focused ? AnyShapeStyle(.tint.opacity(0.4)) : AnyShapeStyle(.quaternary),
                                      hovered: hovered == pane, plate: plate)
                    }
                    .buttonStyle(PressableStyle())
                    .onHover { inside in
                        if inside { hovered = pane } else if hovered == pane { hovered = nil }
                    }
                    .focusable(false)
                    .help(pane.title)
                    .accessibilityLabel(pane.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        // The plate glides to a clicked icon; ↑ ↓ and Reduce Motion move it at once. Hover fades either way.
        .animation(reduceMotion || SettingsMotion.fromKeyboard ? nil : SettingsMotion.settle, value: navigation.pane)
        .animation(SettingsMotion.quick, value: hovered)
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings panes")
        .focusable()
        .focused($focused)
        // The selection's colour shows the focus, as in a sidebar list; a ring round the whole rail would not.
        .focusEffectDisabled()
        .onMoveCommand(perform: move)
    }

    private func move(_ direction: MoveCommandDirection) {
        let step = direction == .down ? 1 : direction == .up ? -1 : 0
        guard step != 0, let index = Self.order.firstIndex(of: navigation.pane) else { return }
        navigation.pane = Self.order[min(max(index + step, 0), Self.order.count - 1)]
    }
}

private extension View {
    /// One rail cell: a 40 × 32 pt hit area, with the sidebar's rounded selection behind it when one is given (one
    /// plate, matched across cells so it moves rather than blinks), else a faint plate while the pointer is on it.
    func railCell(selection: AnyShapeStyle?, hovered: Bool, plate: Namespace.ID) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return frame(width: 40, height: 32)
            .background {
                if let selection {
                    shape.fill(selection).matchedGeometryEffect(id: "selection", in: plate)
                } else if hovered {
                    shape.fill(.quinary).transition(.opacity)
                }
            }
            .contentShape(Rectangle())
    }
}
