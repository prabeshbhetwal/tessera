import SwiftUI

/// Final section of every pane: one verb everywhere, with an optional line saying what is kept.
/// It wipes the pane's settings in one step, so it asks first.
struct ResetSection: View {
    var keeps: String? = nil
    let action: () -> Void
    @State private var confirming = false

    init(keeps: String? = nil, action: @escaping () -> Void) {
        self.keeps = keeps
        self.action = action
    }

    var body: some View {
        Section {
            HStack {
                if let keeps { Caption(keeps) }
                Spacer()
                Button("Restore Defaults\u{2026}") { confirming = true }
                    .settingAnchor("Restore Defaults")
                    .confirmationDialog("Restore this pane\u{2019}s defaults?", isPresented: $confirming, titleVisibility: .visible) {
                        Button("Restore Defaults", role: .destructive, action: action)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if let keeps { Text(keeps) }
                    }
            }
        }
    }
}
