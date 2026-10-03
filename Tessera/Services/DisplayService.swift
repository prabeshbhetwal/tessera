import AppKit
import CoreGraphics
import TesseraCore

/// Lists screens with stable IDs and their resolved grid profiles. Refreshes on screen changes.
@MainActor
final class DisplayService {
    private(set) var displays: [DisplayContext] = []
    var onChange: (@MainActor () -> Void)?

    private let settings: @MainActor () -> TesseraSettings
    // ponytail: never removed; the service lives for the app's lifetime and the block holds self weakly.
    private var observer: NSObjectProtocol?

    init(settings: @escaping @MainActor () -> TesseraSettings) {
        self.settings = settings
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
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    func refresh() {
        let current = settings()
        displays = NSScreen.screens.compactMap { Self.context(for: $0, settings: current) }
    }

    func display(containing p: CGPoint) -> DisplayContext? {
        displays.first { $0.visibleFrame.contains(p) }
    }

    private static func context(for screen: NSScreen, settings: TesseraSettings) -> DisplayContext? {
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
        let padding = override?.padding ?? settings.defaultPadding
        let usable = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        let range = SizingRule.range(for: usable.isNull ? .zero : usable.size, constants: settings.sizing)
        let profile = override?.clamped(to: range)
            ?? .auto(range: range, gap: settings.defaultGap, padding: settings.defaultPadding)
        return DisplayContext(id: id, visibleFrame: screen.visibleFrame, range: range, profile: profile)
    }

    private static func uuidString(for display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
