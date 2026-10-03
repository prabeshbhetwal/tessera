import AppKit
import ApplicationServices
import CoreGraphics

/// TCC permission checks. Accessibility is required; Screen Recording only powers thumbnails.
@MainActor
enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    private static var askedAccessibility = false
    private static var askedScreenCapture = false

    /// First call shows the system prompt, which also adds Tessera to the list. macOS shows that prompt
    /// only once, so later calls open System Settings › Accessibility instead of silently doing nothing.
    /// `freshPrompt` forces the prompt again (after `tccutil reset`, when macOS will show it once more).
    static func promptAccessibility(freshPrompt: Bool = false) {
        guard !askedAccessibility || freshPrompt else {
            openPrivacyPane("Privacy_Accessibility")
            return
        }
        askedAccessibility = true
        // Literal value of kAXTrustedCheckOptionPrompt; avoids touching a C global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens a pane under System Settings › Privacy & Security.
    static func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Calls `onChange` with the fresh trust value whenever the system reports an Accessibility change.
    /// The value lags the notification, so it is re-read 250 ms later. Keep the token to stay subscribed.
    static func observeAccessibility(_ onChange: @escaping @MainActor (Bool) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                onChange(AXIsProcessTrusted())
            }
        }
    }

    static var isScreenCaptureAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Same pattern as `promptAccessibility`: the system prompt once, then the Screen Recording pane.
    /// A grant only takes effect after macOS relaunches Tessera ("Quit & Reopen"); setup resumes there.
    static func requestScreenCapture() {
        guard !askedScreenCapture else {
            openPrivacyPane("Privacy_ScreenCapture")
            return
        }
        askedScreenCapture = true
        if !CGRequestScreenCaptureAccess(), !isScreenCaptureAllowed {
            // Already decided before this launch: no prompt appears, so go straight to the pane.
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }
}
