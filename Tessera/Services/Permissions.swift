import AppKit
import ApplicationServices
import CoreGraphics

/// TCC permission checks. Accessibility is required; Screen Recording only powers thumbnails.
@MainActor
enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (only appears if not yet decided).
    static func promptAccessibility() {
        // Literal value of kAXTrustedCheckOptionPrompt; avoids touching a C global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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

    static func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
    }
}
