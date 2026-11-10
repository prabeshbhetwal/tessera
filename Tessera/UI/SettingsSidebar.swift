import AppKit
import SwiftUI
import TesseraCore

/// Settings sidebar: the pane list, or the settings matching the title bar's search while it holds text.
/// Picking a result opens its pane, scrolls to the row and highlights it.
struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation
    /// Settings › General › App › Understand searches with Apple Intelligence.
    var usesAppleIntelligence: Bool
    /// Settings the on-device model picked for a phrase the local search can't fully read.
    @State private var suggested: [SettingsEntry] = []
    @State private var thinking = false
    @State private var selection: String?
    /// Local matches for the current query, worked out once per change rather than on every redraw.
    @State private var local: [SettingsEntry] = []

    private var trimmed: String { navigation.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [SettingsEntry] {
        let picked = Set(suggested.map(\.id))
        return local.filter { !picked.contains($0.id) }
    }
    private var ordered: [SettingsEntry] { suggested + matches }

    var body: some View {
        Group {
            if trimmed.isEmpty { panes } else { results }
        }
        // ↑ ↓ and Return in the title bar's search field step through and open the results.
        .onChange(of: navigation.searchKey) { _, key in
            if key.step == 0 { reveal(selection ?? ordered.first?.id) } else { move(key.step) }
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
            suggested = picks
            thinking = false
        }
    }

    private var panes: some View {
        List(selection: $navigation.pane) {
            ForEach(SettingsGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(group.panes, id: \.self) { pane in
                        Label { Text(pane.title) } icon: { PaneIcon(pane: pane) }
                            .tag(pane)
                    }
                } header: {
                    if let title = group.title { Text(title) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var results: some View {
        List(selection: $selection) {
            if thinking || !suggested.isEmpty {
                Section("Best match") {
                    ForEach(suggested) { ResultRow(entry: $0).tag($0.id) }
                    if thinking { Label("Reading your search…", systemImage: "sparkle").foregroundStyle(.secondary) }
                }
            }
            if !matches.isEmpty {
                Section(suggested.isEmpty && !thinking ? "Settings" : "More settings") {
                    ForEach(matches) { ResultRow(entry: $0).tag($0.id) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if ordered.isEmpty, !thinking { ContentUnavailableView.search(text: trimmed) }
        }
        .onChange(of: selection) { _, id in reveal(id) }
    }

    /// ↑ ↓ in the search field step through the results without leaving the field.
    private func move(_ step: Int) {
        let ids = ordered.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : ids.count)
        selection = ids[min(max(current + step, 0), ids.count - 1)]
    }

    private func reveal(_ id: String?) {
        guard let id, let entry = ordered.first(where: { $0.id == id }) else { return }
        selection = id
        navigation.reveal(entry)
    }
}

/// What a search depends on; a change to either restarts it.
private struct SearchRun: Equatable {
    let query: String
    let usesAppleIntelligence: Bool
}

/// A result: the setting's name over where it lives, with that pane's icon.
private struct ResultRow: View {
    let entry: SettingsEntry

    var body: some View {
        let pane = SettingsPane(key: entry.pane) ?? .general
        Label {
            VStack(alignment: .leading, spacing: 1) {
                // Wrapped, not cut, in the narrow sidebar.
                Text(entry.title).lineLimit(3)
                Text(entry.section.isEmpty || entry.section == pane.title ? pane.title : "\(pane.title) › \(entry.section)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            PaneIcon(pane: pane)
        }
        .accessibilityElement(children: .combine)
    }
}
