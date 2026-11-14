import AppKit
import Observation
import SwiftUI
import TesseraCore

/// Settings window root: sidebar of panes, grouped form on the right (spec §6.1, M2 §6).
struct SettingsView: View {
    /// Fixed window size in content points (smaller only on a screen that can't fit it). 1180 wide: the sidebar,
    /// the form, and the 420 pt stage (`SettingsDemo`).
    static let width: CGFloat = 1180
    static let height: CGFloat = 720

    @Bindable var model: SettingsModel
    @Bindable var navigation: SettingsNavigation
    var displays: [DisplayContext]

    /// The widest the pane list can be dragged. The icon rail is `SettingsRail.width`.
    static let maxSidebarWidth: CGFloat = 280

    @Environment(\.sidebarRowSize) private var rowSize
    /// Where a drag on the sidebar's edge started from.
    @State private var dragStart: CGFloat?
    /// The control last pointed at in the form, which the stage acts out.
    @State private var cues = DemoCueState()
    /// The pane's width beside the sidebar. On a screen too narrow for the form and the stage side by side, the
    /// stage folds away behind a Preview button rather than squeezing the form.
    @State private var paneWidth: CGFloat = .infinity
    @State private var showsPreview = false

    /// The narrowest the form gets before the stage folds away.
    static let minFormWidth: CGFloat = 520
    private var stageFits: Bool { paneWidth >= StageColumn<EmptyView>.width + Self.minFormWidth }

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

    /// The search field's text. Typing opens the results under the field; clearing it closes them.
    private var query: Binding<String> {
        Binding(get: { navigation.query }, set: { text in
            navigation.query = text
            navigation.resultsOpen = navigation.isSearching
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            pane
        }
        .overlay { if navigation.showsResults { dismissResults } }
        // Centred under the field, which the title bar centres in the window.
        .overlay(alignment: .top) {
            if navigation.showsResults {
                SearchResultsPanel(model: model, navigation: navigation)
                    .padding(.top, 6)
                    .transition(dropTransition)
            }
        }
        .animation(dropAnimation, value: navigation.showsResults)
        .toolbar {
            ToolbarItem(placement: .navigation) { sidebarButton }
            ToolbarItem(placement: .primaryAction) {
                if SettingsDemo.exists(for: navigation.pane) && !stageFits { previewButton }
            }
            // Centred where the title would be: search is the way round Settings, one click away in either mode.
            ToolbarItem(placement: .principal) {
                SearchField(text: query, focusRequests: navigation.searchFocusRequests,
                            onKey: navigation.pressSearchKey,
                            onFocus: navigation.reopenResults)
                    .frame(width: SearchResultsPanel.fieldWidth)
                    .overlay(alignment: .trailing) {
                        // The shortcut, where the clear button sits once there's text.
                        if navigation.query.isEmpty {
                            MiniKeycap("⌘F")
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

    /// Shown only while the stage is folded away: opens it in a popover beside the form.
    private var previewButton: some View {
        Button { showsPreview.toggle() } label: { Label("Preview", systemImage: "play.rectangle") }
            .help("Show what this pane’s settings do")
            .popover(isPresented: $showsPreview, arrowEdge: .bottom) {
                SettingsDemo(pane: navigation.pane, settings: model.settings)
                    .frame(height: 600)
                    .environment(cues)
            }
    }

    private var sidebarButton: some View {
        let compact = navigation.compactSidebar
        return Button { toggleSidebar() } label: { Label("Sidebar", systemImage: "sidebar.left") }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .help(compact ? "Show pane names" : "Show icons only")
            .accessibilityLabel(compact ? "Show pane names" : "Show icons only")
    }

    /// One column for both modes, its width gliding between the pane list and the icon rail. Each keeps its own
    /// width and is clipped while they cross-fade, so neither reflows mid-glide. A hand-made column rather than a
    /// `NavigationSplitView`: that snaps its sidebar shut without animating, and AppKit won't make a sidebar
    /// narrower than the title bar's window buttons and toggle (140 pt).
    private var sidebar: some View {
        let rail = navigation.compactSidebar
        let width = listWidth
        return ZStack(alignment: .topLeading) {
            if rail {
                SettingsRail(navigation: navigation).transition(.opacity)
            } else {
                SettingsSidebar(navigation: navigation)
                    .frame(width: width)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Inside the width frame, so the foot takes the column's width rather than setting it.
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarBrand(navigation: navigation, compact: rail) }
        .frame(width: rail ? SettingsRail.width : width, alignment: .leading)
        .clipped()
        // The look (General › Window look) runs the full height, under the title bar and its window buttons, as the
        // System Settings sidebar does, and meets the pane at a hairline.
        .background {
            WindowBackdrop(look: model.settings.windowMaterial, surface: .sidebar).ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .trailing) {
            // A vertical hairline. (A bare Divider in an overlay draws horizontal: it ruled a stray line across the list.)
            Color(nsColor: .separatorColor).frame(width: 1).ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .trailing) { resizeHandle(from: rail ? SettingsRail.width : width) }
    }


    /// The sidebar's edge: drag it to size the pane list between its fitted width and `maxSidebarWidth`. Dragged
    /// past halfway from the fitted width to the rail, it glides to icons only; dragged back out, to names again.
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
            // The stage runs the pane's full height, beside the header as well as the form.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if navigation.pane != .about { PaneHeader(pane: navigation.pane) }
                    paneView
                }
                // The window look runs behind the form too; its cards stay opaque on top.
                .scrollContentBackground(.hidden)
                // Opaque cards: text in them never depends on what is behind the window.
                .backgroundStyle(Color(nsColor: .controlBackgroundColor))
                .background {
                    WindowBackdrop(look: model.settings.windowMaterial, surface: .pane)
                        .ignoresSafeArea(.container, edges: .top)
                }
                if SettingsDemo.exists(for: navigation.pane) && stageFits {
                    SettingsDemo(pane: navigation.pane, settings: model.settings)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
            .environment(cues)
            .onChange(of: navigation.pane) { cues.cue = nil }
            .onAppear { cues.apply = { [model] change in change(&model.settings) } }
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

    /// The search results drop from the field: a short fall and grow from under it. A fade with Reduce Motion.
    private var dropTransition: AnyTransition {
        reduceMotion ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -6))
    }

    private var dropAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.28, bounce: 0.12)
    }

    /// Behind the open results: a click anywhere else in the window folds them away, keeping the search text.
    private var dismissResults: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { navigation.closeResults() }
            .accessibilityHidden(true)
    }

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
