import AppKit
import SwiftUI
import TesseraCore

/// Settings sidebar: a search field over the pane list. Typing swaps the panes for matching settings;
/// picking one opens its pane, scrolls to the row and highlights it.
struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation
    /// Settings › General › App › Understand searches with Apple Intelligence.
    var usesAppleIntelligence: Bool
    @State private var query = ""
    /// Settings the on-device model picked for a phrase the local search can't fully read.
    @State private var suggested: [SettingsEntry] = []
    @State private var thinking = false
    @State private var selection: String?
    /// Local matches for the current query, worked out once per change rather than on every redraw.
    @State private var local: [SettingsEntry] = []

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [SettingsEntry] {
        let picked = Set(suggested.map(\.id))
        return local.filter { !picked.contains($0.id) }
    }
    private var ordered: [SettingsEntry] { suggested + matches }

    var body: some View {
        VStack(spacing: 0) {
            if navigation.compactSidebar {
                rail
            } else {
                SearchField(text: $query, focusRequests: navigation.searchFocusRequests,
                            focusOnShow: navigation.focusSearchOnShow,
                            onMove: move, onSubmit: { reveal(selection ?? ordered.first?.id) })
                    .onAppear { navigation.focusSearchOnShow = false }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                if trimmed.isEmpty { panes } else { results }
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
    }

    /// The icon-only sidebar: a search button over the pane icons, each named in its tooltip.
    private var rail: some View {
        VStack(spacing: 0) {
            Button { navigation.focusSearch() } label: {
                Image(systemName: "magnifyingglass").frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Search settings (⌘F)")
            .accessibilityLabel("Search settings")
            .padding(.top, 10)
            .padding(.bottom, 4)
            List(selection: $navigation.pane) {
                ForEach(SettingsGroup.allCases, id: \.self) { group in
                    Section {
                        ForEach(group.panes, id: \.self) { pane in
                            Label { Text(pane.title) } icon: { PaneIcon(pane: pane, size: 24) }
                                .labelStyle(.iconOnly)
                                .frame(maxWidth: .infinity)
                                .help(pane.title)
                                .tag(pane)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
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
                Text(entry.title).lineLimit(2)
                Text(entry.section.isEmpty || entry.section == pane.title ? pane.title : "\(pane.title) › \(entry.section)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            PaneIcon(pane: pane)
        }
        .accessibilityElement(children: .combine)
    }
}

/// AppKit's search field: magnifier, clear button and Esc to clear, plus ↑ ↓ and Return for the results.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    /// Bumped by ⌘F; each new value focuses the field.
    let focusRequests: Int
    /// Focus the field as soon as it is in the window (the icon sidebar's search button and ⌘F).
    var focusOnShow = false
    let onMove: (Int) -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        if focusOnShow { DispatchQueue.main.async { field.window?.makeFirstResponder(field) } }
        field.placeholderString = "Search settings"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        // The clear button and Esc send the action, not a text-change notification.
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.setAccessibilityLabel("Search settings")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        var focusRequests: Int

        init(parent: SearchField) {
            self.parent = parent
            focusRequests = parent.focusRequests
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func changed(_ field: NSSearchField) {
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            default: return false
            }
            return true
        }
    }
}
