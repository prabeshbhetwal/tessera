import SwiftUI

/// Icon-only copy button for the line it copies: the copy glyph turns into a tick for about two seconds after
/// copying (instant under Reduce Motion). Put it beside the text, not in a separate row.
struct CopyButton: View {
    let text: String
    /// Tooltip and VoiceOver name while idle, e.g. "Copy version".
    var label = "Copy"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var resetCopied: Task<Void, Never>?

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(copied ? "Copied" : label)
        .accessibilityLabel(copied ? "Copied" : label)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        resetCopied?.cancel()
        resetCopied = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
