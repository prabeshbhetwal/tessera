import AppKit
import SwiftUI
import TesseraCore

/// The title bar search's results, dropped down under the field. The on-device model's best matches come first, then
/// the rest grouped by pane under that pane's icon, panes in the order of their best match. ↑ ↓ and Return in the
/// field move and open, and so does the pointer. An on/off setting carries its own switch, so it can be flipped right
/// here; anything else opens its pane, scrolled to the row and highlighted.
struct SearchResultsPanel: View {
    @Bindable var model: SettingsModel
    @Bindable var navigation: SettingsNavigation
    /// Settings the on-device model picked for a phrase the local search can't fully read.
    @State private var suggested: [SettingsEntry] = []
    @State private var thinking = false
    /// Local matches for the current query, worked out once per change rather than on every redraw.
    @State private var local: [SettingsEntry]
    @State private var selection: String?
    /// The rows' measured height; the list is that tall, up to `maxListHeight`.
    @State private var rowsHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 440
    /// The title bar's search field, centred over the panel.
    static let fieldWidth: CGFloat = 320
    /// Taller than this, the list scrolls.
    private static let maxListHeight: CGFloat = 420

    init(model: SettingsModel, navigation: SettingsNavigation) {
        self.model = model
        self.navigation = navigation
        // Filled now, not in the task, so the panel never opens on a flash of "no matches".
        _local = State(initialValue: SettingsSearch.results(for: navigation.query))
    }

    private var usesAppleIntelligence: Bool { model.settings.searchUsesAppleIntelligence }
    private var trimmed: String { navigation.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Local matches the model didn't already pick, by pane.
    private var groups: [ResultGroup] {
        let picked = Set(suggested.map(\.id))
        var groups: [ResultGroup] = []
        for entry in local where !picked.contains(entry.id) {
            if let i = groups.firstIndex(where: { $0.pane == entry.pane }) { groups[i].entries.append(entry) }
            else { groups.append(ResultGroup(pane: entry.pane, entries: [entry])) }
        }
        return groups
    }

    /// Every result in the order shown, for ↑ ↓.
    private var ordered: [SettingsEntry] { suggested + groups.flatMap(\.entries) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let empty = ordered.isEmpty && !thinking
        VStack(spacing: 0) {
            // Typing between "no matches" and some cross-fades; the results' height itself never animates, so typing
            // doesn't make the panel wobble.
            if empty { noMatches.transition(.opacity) } else { list.transition(.opacity) }
            Divider()
            footer
        }
        .animation(SettingsMotion.quick, value: empty)
        .frame(width: Self.width)
        // Solid, a step up from the window: a translucent material let the pane's controls smear through.
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search results")
        .onChange(of: navigation.searchKey) { _, key in
            switch key.action {
            case .move(let step): move(step)
            case .open: open(selection ?? ordered.first?.id)
            case .flip: flip(selection ?? ordered.first?.id)
            }
        }
        // The switch is part of the identity: turning it off cancels a model request and drops its picks.
        .task(id: SearchRun(query: trimmed, usesAppleIntelligence: usesAppleIntelligence)) {
            local = SettingsSearch.results(for: trimmed)
            if let selected = selection, !ordered.contains(where: { $0.id == selected }) { selection = nil }
            guard usesAppleIntelligence, SettingsAssistant.isAvailable, SettingsAssistant.shouldAsk(trimmed, localResults: local.count)
            else { suggested = []; thinking = false; return }
            // The previous picks stay until new ones arrive, so the list doesn't flicker while typing.
            thinking = true
            // Wait for a pause in typing; a new keystroke cancels this task.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let picks = await SettingsAssistant.suggest(for: trimmed)
            guard !Task.isCancelled else { return }
            withAnimation(SettingsMotion.quick) {
                suggested = picks
                thinking = false
            }
        }
    }

    /// Sized to the results; past `maxListHeight` they scroll. Until the rows are measured, a close estimate.
    private var list: some View {
        let estimate = CGFloat(ordered.count) * 44 + CGFloat(groups.count + (suggested.isEmpty ? 0 : 1)) * 30 + 12
        return ScrollViewReader { proxy in
            ScrollView {
                rows.onGeometryChange(for: CGFloat.self, of: \.size.height) { rowsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(rowsHeight ?? estimate, Self.maxListHeight))
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1) {
            if thinking || !suggested.isEmpty {
                GroupHeader(title: "Best match") { Image(systemName: "sparkle") }
                // The model's picks arrive after a pause in typing: they fade in rather than pop.
                ForEach(suggested) { row($0, showsPane: true).transition(.opacity) }
                if thinking {
                    Label("Reading your search…", systemImage: "sparkle")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            ForEach(groups) { group in
                let pane = SettingsPane(key: group.pane) ?? .general
                GroupHeader(title: pane.title) { PaneIcon(pane: pane, size: 16) }
                ForEach(group.entries) { row($0, showsPane: false) }
            }
        }
        .padding(6)
    }

    private func row(_ entry: SettingsEntry, showsPane: Bool) -> some View {
        let quick = SearchQuickToggles.switch(for: entry)
        return ResultRow(
            entry: entry, query: trimmed, showsPane: showsPane, selected: selection == entry.id,
            isOn: quick.map { quick in
                Binding(get: { model.settings[keyPath: quick.path] }, set: { model.settings[keyPath: quick.path] = $0 })
            },
            switchEnabled: quick?.enabled(model.settings) ?? true,
            onOpen: { open(entry.id) }
        )
        .id(entry.id)
        .onHover { if $0 { selection = entry.id } }
    }

    private var noMatches: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text("No settings match \u{201C}\(trimmed)\u{201D}").font(.headline).lineLimit(2)
            Text("Try another word, such as colour or shortcut.").font(.callout).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(keys: ["↑", "↓"], action: "Move")
            KeyHint(keys: ["↩"], action: "Open")
            if ordered.contains(where: { SearchQuickToggles.switch(for: $0) != nil }) {
                KeyHint(keys: ["⌥", "↩"], action: "Switch")
            }
            KeyHint(keys: ["Esc"], action: "Clear")
            Spacer(minLength: 0)
            if usesAppleIntelligence, SettingsAssistant.isAvailable {
                Label("Apple Intelligence", systemImage: "sparkle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // The same keys are announced with the field; the footer only shows them.
        .accessibilityHidden(true)
    }

    /// ↑ ↓ in the search field step through the results without leaving the field.
    private func move(_ step: Int) {
        let ids = ordered.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : ids.count)
        let next = ids[min(max(current + step, 0), ids.count - 1)]
        selection = next
        // Focus stays in the field, so VoiceOver has to be told which result is now highlighted.
        if let entry = ordered.first(where: { $0.id == next }) {
            let pane = SettingsPane(key: entry.pane) ?? .general
            AccessibilityNotification.Announcement("\(entry.title), \(pane.title)").post()
        }
    }

    /// ⌥Return: flips the result's switch where it has one the pane would let change, and says the new state.
    private func flip(_ id: String?) {
        guard let id, let entry = ordered.first(where: { $0.id == id }),
              let quick = SearchQuickToggles.switch(for: entry), quick.enabled(model.settings)
        else { NSSound.beep(); return }
        selection = id
        model.settings[keyPath: quick.path].toggle()
        AccessibilityNotification.Announcement("\(entry.title), \(model.settings[keyPath: quick.path] ? "on" : "off")").post()
    }

    /// Opens the result's pane at its row and folds the results away; the search text stays to come back to.
    private func open(_ id: String?) {
        guard let id, let entry = ordered.first(where: { $0.id == id }) else { return }
        selection = id
        navigation.reveal(entry)
        navigation.closeResults()
    }
}

/// What a search depends on; a change to either restarts it.
private struct SearchRun: Equatable {
    let query: String
    let usesAppleIntelligence: Bool
}

private struct ResultGroup: Identifiable {
    let pane: String
    var entries: [SettingsEntry]
    var id: String { pane }
}
