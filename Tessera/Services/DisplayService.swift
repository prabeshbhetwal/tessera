import AppKit
import CoreGraphics
import TesseraCore

/// Lists screens with stable IDs and their resolved grid profiles. Refreshes on screen changes.
@MainActor
final class DisplayService {
    private(set) var displays: [DisplayContext] = []
    var onChange: (@MainActor () -> Void)?

    private let settings: @MainActor () -> TesseraSettings
    private let suppliedSnapshots: (@MainActor () -> [DisplayContext])?
    // ponytail: never removed; the service lives for the app's lifetime and the block holds self weakly.
    private var observer: NSObjectProtocol?

    init(settings: @escaping @MainActor () -> TesseraSettings, displays: [DisplayContext]? = nil,
         snapshotProvider: (@MainActor () -> [DisplayContext])? = nil) {
        self.settings = settings
        if let snapshotProvider { suppliedSnapshots = snapshotProvider }
        else if let displays { suppliedSnapshots = { displays } }
        else { suppliedSnapshots = nil }
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.onChange?()
            }
        }
    }

    /// Height of the primary (menu-bar) screen, used for AX ↔ AppKit conversion. 0 when headless.
    static var primaryHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    func refresh() {
        if let suppliedSnapshots { displays = suppliedSnapshots(); return }
        let current = settings()
        displays = NSScreen.screens.compactMap { Self.context(for: $0, settings: current) }
    }

    func display(containing p: CGPoint) -> DisplayContext? {
        displays.display(at: p)
    }

    static func context(for screen: NSScreen, settings: TesseraSettings) -> DisplayContext? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let cgID = CGDirectDisplayID(number.uint32Value)
        let id = DisplayID(
            vendor: CGDisplayVendorNumber(cgID),
            model: CGDisplayModelNumber(cgID),
            serial: CGDisplaySerialNumber(cgID),
            uuid: uuidString(for: cgID)
        )

        let override = settings.displayOverrides[id.storageKey]
        // Sized from the visible frame before padding, so padding never costs a column (CHG90 → 3–6).
        let range = SizingRule.range(for: screen.visibleFrame.size, constants: settings.sizing)
        let profile = override?.clamped(to: range)
            ?? .auto(range: range, gap: settings.defaultGap, padding: settings.defaultPadding)
        return DisplayContext(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame, range: range, profile: profile)
    }

    private static func uuidString(for display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
