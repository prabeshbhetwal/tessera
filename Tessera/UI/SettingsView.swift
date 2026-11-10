import AppKit
import Observation
import SwiftUI
import TesseraCore

/// Settings window root: sidebar of panes, grouped form on the right (spec §6.1, M2 §6).
struct SettingsView: View {
    /// Fixed window size in content points (smaller only on a screen that can't fit it).
    static let width: CGFloat = 820
    static let height: CGFloat = 720

    @Bindable var model: SettingsModel
    @Bindable var navigation: SettingsNavigation
    var displays: [DisplayContext]

    /// The widest the pane list can be dragged. The icon rail is `SettingsRail.width`.
    static let maxSidebarWidth: CGFloat = 280

    @Environment(\.sidebarRowSize) private var rowSize
    /// Where a drag on the sidebar's edge started from.
    @State private var dragStart: CGFloat?

    /// The narrowest the pane list goes: the longest pane name in full at the system's sidebar text size, after the
    /// list's 42 pt inset and icon, with an 18 pt gap before the trailing edge. Narrower than this, it becomes icons.
    private var fittedWidth: CGFloat {
        let size: CGFloat = switch rowSize { case .small: 11; case .large: 15; default: 13 }
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let longest = SettingsPane.allCases.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
        return ceil(longest.max() ?? 0) + 60
    }

    /// The pane list's width: as last dragged, else the fitted width plus a little air.
    private var listWidth: CGFloat {
        let fitted = fittedWidth
        guard navigation.sidebarWidth > 0 else { return fitted + 12 }
        return min(max(navigation.sidebarWidth, fitted), max(Self.maxSidebarWidth, fitted))
    }

    /// The search field's text. Typing the first letter or clearing the last one over icons only swaps the rail
    /// for the results and back, with the same glide as the sidebar button.
    private var query: Binding<String> {
        Binding(get: { navigation.query }, set: { text in
            let searching = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let swaps = navigation.compactSidebar && searching != navigation.isSearching
            withAnimation(swaps ? glide : nil) { navigation.query = text }
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            pane
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { sidebarButton }
            // At the title bar's trailing end: one click to search, even from icons only.
            ToolbarItem { Spacer() }
            ToolbarItem {
                SearchField(text: query, focusRequests: navigation.searchFocusRequests,
                            onMove: navigation.pressSearchKey, onSubmit: { navigation.pressSearchKey(0) })
                    .frame(width: 200)
                    .overlay(alignment: .trailing) {
                        // The shortcut, where the clear button sits once there's text.
                        if navigation.query.isEmpty {
                            Text("⌘F")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .padding(.trailing, 7)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .background {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                if let key = pane.shortcutKey {
                    KeyCommand(KeyEquivalent(key)) { navigation.pane = pane }
                }
            }
            KeyCommand("f") { navigation.focusSearch() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarButton: some View {
        let compact = navigation.compactSidebar
        return Button { toggleSidebar() } label: { Label("Sidebar", systemImage: "sidebar.left") }
            .keyboardShortcut("s", modifiers: [.control, .command])
            // Search results hold the sidebar open; switching modes then would change nothing you can see.
            .disabled(navigation.isSearching)
            .help(compact ? "Show pane names" : "Show icons only")
            .accessibilityLabel(compact ? "Show pane names" : "Show icons only")
    }

    /// One column for both modes, its width gliding between the pane list and the icon rail. Each keeps its own
    /// width and is clipped while they cross-fade, so neither reflows mid-glide. A hand-made column rather than a
    /// `NavigationSplitView`: that snaps its sidebar shut without animating, and AppKit won't make a sidebar
    /// narrower than the title bar's window buttons and toggle (140 pt).
    private var sidebar: some View {
        let rail = navigation.showsRail
        let width = listWidth
        return ZStack(alignment: .topLeading) {
            if rail {
                SettingsRail(navigation: navigation).transition(.opacity)
            } else {
                SettingsSidebar(navigation: navigation, usesAppleIntelligence: model.settings.searchUsesAppleIntelligence)
                    .frame(width: width)
                    .transition(.opacity)
            }
        }
        .frame(width: rail ? SettingsRail.width : width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        // On the window's own background, like the pane, with a hairline between them.
        .overlay(alignment: .trailing) { Divider() }
        .overlay(alignment: .trailing) { resizeHandle(from: rail ? SettingsRail.width : width) }
    }

    /// The sidebar's edge: drag it to size the pane list between its fitted width and `maxSidebarWidth`. Dragged
    /// past halfway from the fitted width to the rail, it glides to icons only; dragged back out, to names again.
    /// While search results show, it only resizes.
    private func resizeHandle(from width: CGFloat) -> some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? width
                    dragStart = start
                    let proposed = start + drag.translation.width
                    let fitted = fittedWidth
                    let clamped = min(max(proposed, fitted), Self.maxSidebarWidth)
                    // Search results hold the list open and leave the icons-only choice alone, as the sidebar
                    // button does: clearing the search still returns to the rail.
                    guard !navigation.isSearching else { navigation.sidebarWidth = clamped; return }
                    let icons = proposed < (SettingsRail.width + fitted) / 2
                    if icons != navigation.compactSidebar { withAnimation(glide) { navigation.compactSidebar = icons } }
                    if !icons { navigation.sidebarWidth = clamped }
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityHidden(true)
    }

    /// The pane's header over its form, scrolled to a search result's row when one is revealed.
    private var pane: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if navigation.pane != .about { PaneHeader(pane: navigation.pane) }
                paneView
            }
            .environment(\.settingsPaneKey, navigation.pane.key)
            .environment(\.settingsHighlight, navigation.highlight)
            .task(id: navigation.reveals) { await scrollToHighlight(proxy) }
        }
        // idealHeight 0: a grouped Form's ideal height is its full content (up to ~1100 pt). Sized from that, the
        // content was taller than the window and AppKit centred it, hiding the sidebar top and pane header under
        // the title bar. Now it fills the window and the Form scrolls.
        .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sidebar's glide between names and icons. Instant with Reduce Motion.
    private var glide: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }

    private func toggleSidebar() {
        withAnimation(glide) { navigation.compactSidebar.toggle() }
    }

    /// After a search reveal: let the new pane lay out, bring the row to the middle, then fade the highlight.
    private func scrollToHighlight(_ proxy: ScrollViewProxy) async {
        guard let id = navigation.highlight else { return }
        // Twice: a pane that takes longer to lay out than the first wait misses the first scroll.
        for wait in [80, 250] {
            try? await Task.sleep(for: .milliseconds(wait))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, navigation.highlight == id else { return }
        navigation.highlight = nil
    }

    @ViewBuilder private var paneView: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .updates: UpdatesPane(model: model)
        case .excludedApps: ExcludedAppsPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .cycles: CyclesPane(model: model)
        case .splits: SplitsPane(model: model, displays: displays)
        case .displays: DisplaysPane(model: model, displays: displays)
        case .ring: RingPane(model: model)
        case .overlay: OverlayPane(model: model)
        case .motion: MotionPane(model: model)
        case .about: AboutPane()
        }
    }
}

#Preview {
    SettingsView(model: SettingsModel(), navigation: SettingsNavigation(), displays: [])
}
