import SwiftUI

/// Section title with an optional ⓘ at the trailing edge. The pane stays brief; the explanation is one click
/// (or Space) away in a popover. Warnings and live state still go in a `Footer` or `Callout`, never in here.
struct InfoHeader: View {
    let title: String
    var info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let info { InfoButton(topic: title, text: info) }
        }
    }
}

/// ⓘ that opens a short explanation. VoiceOver reads it as "About <topic>".
struct InfoButton: View {
    let topic: String
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle")
                .imageScale(.medium)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("About \(topic)")
        .accessibilityLabel("About \(topic)")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(14)
        }
    }
}
