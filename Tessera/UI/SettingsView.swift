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

    /// The full sidebar's width. The icon rail is `SettingsRail.width`.
    static let sidebarWidth: CGFloat = 230

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
        return ZStack(alignment: .topLeading) {
            if rail {
                SettingsRail(navigation: navigation).transition(.opacity)
            } else {
                SettingsSidebar(navigation: navigation, usesAppleIntelligence: model.settings.searchUsesAppleIntelligence)
                    .frame(width: Self.sidebarWidth)
                    .transition(.opacity)
            }
        }
        .frame(width: rail ? SettingsRail.width : Self.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(SidebarMaterial())
        .overlay(alignment: .trailing) { Divider() }
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
