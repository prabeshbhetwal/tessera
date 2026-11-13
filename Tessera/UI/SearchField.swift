import AppKit
import SwiftUI

/// The Settings title bar's search field: AppKit's magnifier, clear button and Esc to clear, plus ↑ ↓ and Return
/// for the results that drop down under it.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    /// Bumped by ⌘F; each new value focuses the field.
    let focusRequests: Int
    /// ↑ ↓ (−1, 1), Return and ⌥Return, for the results under the field.
    let onKey: (SearchKey.Action) -> Void
    /// The field took the keyboard: a click into it or ⌘F.
    let onFocus: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusReportingSearchField()
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.parent.onFocus() }
        field.placeholderString = "Search Tessera"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        // The clear button and Esc send the action, not a text-change notification.
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.setAccessibilityLabel("Search Tessera settings")
        field.setAccessibilityHelp("Up and Down choose a result, Return opens it, Option-Return flips its switch.")
        field.toolTip = "Search Tessera settings (⌘F)"
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
            case #selector(NSResponder.moveDown(_:)): parent.onKey(.move(1))
            case #selector(NSResponder.moveUp(_:)): parent.onKey(.move(-1))
            case #selector(NSResponder.insertNewline(_:)): parent.onKey(.open)
            // ⌥Return: Space can't flip a switch here, it types in the field.
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): parent.onKey(.flip)
            default: return false
            }
            return true
        }
    }
}

/// Reports each time it takes the keyboard. A click while it already has it doesn't count, so closing the results
/// also gives the keyboard up (`SettingsNavigation.closeResults`), and the next click brings them back.
private final class FocusReportingSearchField: NSSearchField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { onFocus?() }
        return took
    }
}
