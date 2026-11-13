import AppKit

/// Speaks a short message through VoiceOver at high priority, the way the ring's selection label is spoken.
/// The overlay panels never take focus, so VoiceOver would not notice their text on its own.
@MainActor
enum VoiceOverAnnouncement {
    /// A no-op unless VoiceOver is running: announcing is an accessibility round trip.
    static func post(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
