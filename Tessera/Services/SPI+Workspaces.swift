import AppKit
import Darwin
import Foundation

extension SPI {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    /// Read-only optional Space identity. Tiling remains available when the OS does not expose this information.
    static func activeWorkspaceIDs() -> [String: UInt64]? {
        guard let handle = workspaceSymbols,
              let main = dlsym(handle, "CGSMainConnectionID"),
              let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        let connection = unsafeBitCast(main, to: Connection.self)()
        guard let value = unsafeBitCast(copy, to: CopySpaces.self)(connection)?.takeRetainedValue(),
              let rows = value as? [[String: Any]] else { return nil }
        var byUUID: [String: UInt64] = [:]
        for row in rows {
            guard let uuid = row["Display Identifier"] as? String,
                  let current = row["Current Space"] as? [String: Any],
                  let number = (current["ManagedSpaceID"] ?? current["id64"]) as? NSNumber else { continue }
            byUUID[uuid] = number.uint64Value
        }
        let topology = WindowTopology.system()
        var result: [String: UInt64] = [:]
        for display in topology.displays {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(display.number)?.takeRetainedValue(),
                  let space = byUUID[CFUUIDCreateString(nil, uuid) as String] else { return nil }
            // Ambiguous display identities cannot safely identify an origin workspace.
            guard result[display.key] == nil else { return nil }
            result[display.key] = space
        }
        return result
    }

    nonisolated(unsafe) private static let workspaceSymbols = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
}
