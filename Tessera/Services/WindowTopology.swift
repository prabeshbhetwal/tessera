import AppKit
import TesseraCore

struct WindowTopology: Equatable, Sendable {
    struct Display: Equatable, Sendable {
        let number: CGDirectDisplayID
        let key: String
        let bounds: CGRect
    }
    let primary: CGDirectDisplayID
    let displays: [Display]

    var keys: Set<String> { Set(displays.map(\.key)) }
    var primaryHeight: CGFloat { displays.first { $0.number == primary }?.bounds.height ?? 0 }
    var recoveryDisplays: [WindowPlacementSnapshot.Display] {
        displays.map { .init(key: $0.key, bounds: $0.bounds) }
    }
    func placement(_ frame: CGRect) -> WindowPlacementSnapshot {
        let display = displays.first { $0.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        return WindowPlacementSnapshot(frame: frame, display: display.map { .init(key: $0.key, bounds: $0.bounds) })
    }
    func key(containing frame: CGRect) -> String? {
        displays.first { $0.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) }?.key
    }
    func contains(_ display: DisplayContext) -> Bool {
        guard let screen = displays.first(where: { $0.key == display.id.storageKey }) else { return false }
        let expected = CoordinateSpace.fromAX(screen.bounds, primaryHeight: primaryHeight)
        return max(abs(expected.minX - display.frame.minX), abs(expected.maxX - display.frame.maxX),
                   abs(expected.minY - display.frame.minY), abs(expected.maxY - display.frame.maxY)) <= 1
    }

    static func system() -> WindowTopology {
        var count: UInt32 = 0
        let primary = CGMainDisplayID()
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return WindowTopology(primary: primary, displays: [])
        }
        var numbers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &numbers, &count) == .success else {
            return WindowTopology(primary: primary, displays: [])
        }
        let displays = numbers.prefix(Int(count)).sorted().map { number in
            let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
            let identity = DisplayID(vendor: CGDisplayVendorNumber(number), model: CGDisplayModelNumber(number),
                                     serial: CGDisplaySerialNumber(number),
                                     uuid: uuid.map { CFUUIDCreateString(nil, $0) as String })
            return Display(number: number, key: identity.storageKey, bounds: CGDisplayBounds(number))
        }
        return WindowTopology(primary: primary, displays: displays)
    }
}
