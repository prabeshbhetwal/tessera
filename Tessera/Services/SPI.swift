import ApplicationServices
import Darwin
import os

/// Private API loader. Every symbol is resolved with `dlsym` and is optional:
/// a missing symbol turns the feature off, it never crashes.
enum SPI {
    typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let logger = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "SPI")

    /// `_AXUIElementGetWindow`: AX window element → CGWindowID. Nil when the symbol is missing.
    static let axGetWindow: AXGetWindowFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
            logger.notice("_AXUIElementGetWindow unavailable; window IDs disabled")
            return nil
        }
        return unsafeBitCast(symbol, to: AXGetWindowFunction.self)
    }()

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: CGWindowID = 0
        guard axGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}
