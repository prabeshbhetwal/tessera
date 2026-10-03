import CoreGraphics
import os
import ScreenCaptureKit

/// One ScreenCaptureKit snapshot per session, with a 150 ms budget. Nil on timeout, error or no permission.
actor ThumbnailService {
    private static let budget: Duration = .milliseconds(150)

    func snapshot(windowID: CGWindowID) async -> CGImage? {
        // Preflight only: never trigger the Screen Recording prompt from the hot path.
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let gate = FirstResult()
        return await withCheckedContinuation { continuation in
            gate.arm(continuation)
            let capture = Task {
                gate.finish(await Self.capture(windowID))
            }
            Task {
                try? await Task.sleep(for: Self.budget)
                gate.finish(nil)
                capture.cancel()
            }
        }
    }

    private static func capture(_ windowID: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = max(1, Int(filter.contentRect.width * scale))
            config.height = max(1, Int(filter.contentRect.height * scale))
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }
}

/// Resumes a continuation with whichever result arrives first; later results are dropped.
private final class FirstResult: Sendable {
    private let continuation = OSAllocatedUnfairLock<CheckedContinuation<CGImage?, Never>?>(uncheckedState: nil)

    func arm(_ c: CheckedContinuation<CGImage?, Never>) {
        continuation.withLockUnchecked { $0 = c }
    }

    func finish(_ image: CGImage?) {
        let c = continuation.withLockUnchecked { state -> CheckedContinuation<CGImage?, Never>? in
            defer { state = nil }
            return state
        }
        c?.resume(returning: image)
    }
}
