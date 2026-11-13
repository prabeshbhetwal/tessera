import SwiftUI
import TesseraCore

/// A result: the setting's name, with the typed words in bold, over where it lives. Under "Best match" it also
/// shows its pane's icon. A switch when it can be flipped here, else a Return glyph while it is selected.
struct ResultRow: View {
    let entry: SettingsEntry
    let query: String
    let showsPane: Bool
    let selected: Bool
    let isOn: Binding<Bool>?
    let switchEnabled: Bool
    let onOpen: () -> Void

    var body: some View {
        let pane = SettingsPane(key: entry.pane) ?? .general
        HStack(spacing: 10) {
            if showsPane { PaneIcon(pane: pane, size: 22) }
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.emphasised(entry.title, query)).lineLimit(2)
                if let place = place(pane) {
                    Text(place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onOpen)
            Spacer(minLength: 8)
            if let isOn {
                // Named for the setting, so VoiceOver tells the rows' switches apart.
                Toggle(entry.title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!switchEnabled)
            } else {
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        // Grouped rows line their text up with the group's name, past its icon.
        .padding(.leading, showsPane ? 8 : 30)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    /// "Pane › Section" under a best match; under a pane's group, just the section when it says something new.
    private func place(_ pane: SettingsPane) -> String? {
        let section = entry.section.isEmpty || entry.section == pane.title ? nil : entry.section
        guard showsPane else { return section }
        return section.map { "\(pane.title) › \($0)" } ?? pane.title
    }

    /// The title with each typed word of two or more letters in bold where it starts a word.
    static func emphasised(_ title: String, _ query: String) -> AttributedString {
        var text = AttributedString(title)
        for word in query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where word.count >= 2 {
            var from = text.startIndex
            while let range = text[from...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                let startsWord = range.lowerBound == text.startIndex
                    || !text.characters[text.characters.index(before: range.lowerBound)].isLetter
                if startsWord { text[range].inlinePresentationIntent = .stronglyEmphasized }
                from = range.upperBound
            }
        }
        return text
    }
}

struct GroupHeader<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 6) {
            icon.frame(width: 16)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Keycaps and what they do, for the results' footer.
struct KeyHint: View {
    let keys: [String]
    let action: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { MiniKeycap($0) }
            Text(action).padding(.leading, 2)
        }
    }
}

/// A small keycap for shortcut hints: the search field's ⌘F and the results' footer.
struct MiniKeycap: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
