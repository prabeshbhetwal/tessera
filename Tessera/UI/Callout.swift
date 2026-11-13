import SwiftUI

/// Inline notice with an icon: side effects, warnings and results that a plain caption would bury.
struct Callout<Action: View>: View {
    enum Kind { case info, warning, success }

    let kind: Kind
    let text: String
    let action: Action

    init(_ kind: Kind, _ text: String, @ViewBuilder action: () -> Action) {
        self.kind = kind
        self.text = text
        self.action = action()
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .info: .secondary
        case .warning: .orange
        case .success: .green
        }
    }

    /// What VoiceOver says for the symbol, so a warning, a result and a note are told apart.
    private var kindLabel: String {
        switch kind {
        case .info: "Note"
        case .warning: "Warning"
        case .success: "Done"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityLabel(kindLabel)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(10)
        .quinaryPanel()
        .accessibilityElement(children: .contain)
    }
}

extension Callout where Action == EmptyView {
    init(_ kind: Kind, _ text: String) {
        self.init(kind, text) { EmptyView() }
    }
}
