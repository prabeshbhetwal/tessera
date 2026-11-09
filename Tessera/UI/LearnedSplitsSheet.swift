import AppKit
import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

/// One display's learned splits, opened from Settings › Splits › Manage…: search by app, forget one (its
/// minus button, or select several and press Delete), or forget everything learned on that display.
/// Closes itself when the last split is gone.
struct LearnedSplitsSheet: View {
    let title: String
    let splits: [LearnedSplit]
    let forget: ([SplitKey]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = Set<SplitKey>()
    @State private var confirmingForgetAll = false
    @State private var confirmingForgetSelected = false

    private var shown: [LearnedSplit] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return splits }
        return splits.filter { split in
            let apps = SplitLabel.apps(split.key)
            return words.allSatisfy { apps.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(Self.count(splits.count)).foregroundStyle(.secondary).monospacedDigit()
            }
            TextField("Search apps", text: $query, prompt: Text("Search apps"))
                .textFieldStyle(.roundedBorder)
                .onSubmit {}  // Return searches; it must not reach Done and close the sheet.
            List(selection: $selection) {
                ForEach(shown, id: \.key) { split in
                    LearnedSplitRow(split: split) { forget([split.key]) }
                        .tag(split.key)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand(perform: askToForgetSelection)
            .overlay {
                if shown.isEmpty, !query.isEmpty { ContentUnavailableView.search(text: query) }
            }
            HStack {
                Button("Forget All on This Display…", role: .destructive) { confirmingForgetAll = true }
                Spacer()
                if !selection.isEmpty {
                    Button("Forget \(selection.count) Selected", action: askToForgetSelection)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onExitCommand { dismiss() }
        // Never act on rows the search hides.
        .onChange(of: query) { _, _ in selection.formIntersection(shown.map(\.key)) }
        .padding(20)
        .frame(width: 540, height: 460)
        .onChange(of: splits.isEmpty) { _, empty in if empty { dismiss() } }
        .confirmationDialog("Forget all \(Self.count(splits.count)) on \(title)?",
                            isPresented: $confirmingForgetAll, titleVisibility: .visible) {
            Button("Forget All", role: .destructive) { forget(splits.map(\.key)) }
        } message: {
            Text("Tessera uses equal shares for these apps until it learns them again.")
        }
        .confirmationDialog("Forget \(Self.count(selection.count))?",
                            isPresented: $confirmingForgetSelected, titleVisibility: .visible) {
            Button("Forget", role: .destructive, action: forgetSelection)
        } message: {
            Text("Tessera uses equal shares for these apps until it learns them again.")
        }
    }

    /// One split goes at once, like its ⊖; several ask first.
    private func askToForgetSelection() {
        if selection.count > 1 { confirmingForgetSelected = true } else { forgetSelection() }
    }

    private func forgetSelection() {
        guard !selection.isEmpty else { return }
        forget(Array(selection))
        selection = []
    }

    static func count(_ n: Int) -> String { n == 1 ? "1 split" : "\(n) splits" }
}

/// One learned split: its apps' icons and names, when it was learned, and a button to forget it.
private struct LearnedSplitRow: View {
    let split: LearnedSplit
    let forget: () -> Void

    var body: some View {
        let apps = SplitLabel.apps(split.key)
        HStack(spacing: 10) {
            AppIconStack(bundleIDs: split.key.apps)
            VStack(alignment: .leading, spacing: 2) {
                Text(apps).lineLimit(1).truncationMode(.tail)
                Text("Learned \(split.updated, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: forget) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Forget this split")
            .accessibilityLabel("Forget \(apps)")
        }
        .padding(.vertical, 2)
    }
}

/// Up to four app icons, overlapping a little, so a split is recognisable at a glance.
private struct AppIconStack: View {
    let bundleIDs: [String]

    var body: some View {
        var seen = Set<String>()
        let unique = bundleIDs.filter { seen.insert($0).inserted }.prefix(4)
        HStack(spacing: -6) {
            ForEach(Array(unique), id: \.self) { id in
                Image(nsImage: AppIcon.image(for: id))
                    .resizable()
                    .frame(width: 22, height: 22)
            }
        }
        .frame(width: 22 + 16 * 3, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// App icons by bundle ID, looked up once per run.
@MainActor
private enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for bundleID: String) -> NSImage {
        if let image = cache[bundleID] { return image }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)
        cache[bundleID] = image
        return image
    }
}
