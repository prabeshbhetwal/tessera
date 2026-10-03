import Darwin
import Foundation
import os
import TesseraCore

/// Unix-domain socket the `tessera` CLI talks to (M2 spec §5).
/// Protocol: one request line (`Command` JSON) → one response line (`CommandResult` JSON), then close.
@MainActor
final class SocketServer {
    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tessera", isDirectory: true)
            .appendingPathComponent("tessera.sock")
    }

    private let url: URL?
    private var source: (any DispatchSourceRead)?
    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "socket")
    private nonisolated static let acceptQueue = DispatchQueue(label: "com.prabeshbhetwal.Tessera.socket")
    private nonisolated static let maxRequestBytes = 64 * 1024

    init(url: URL? = SocketServer.defaultURL) {
        self.url = url
    }

    func start() {
        guard source == nil else { return }
        guard let url else {
            Self.log.fault("no Application Support directory; CLI socket disabled")
            return
        }
        let fd: Int32
        do {
            fd = try Self.listen(at: url)
        } catch {
            Self.log.error("CLI socket failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        source = Self.makeAcceptSource(fd)
    }

    func stop() {
        // Only the instance that is listening owns the socket file; a second launch quitting must not remove it.
        guard let source else { return }
        source.cancel()
        self.source = nil
        if let url { unlink(url.path) }
    }

    // MARK: - Listening

    private nonisolated static func listen(at url: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = url.path
        unlink(path) // stale socket from a previous run; ENOENT is fine
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        guard let bound = withUnixAddress(path, { bind(fd, $0, $1) }) else {
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG),
                          userInfo: [NSLocalizedDescriptionKey: "socket path too long: \(path)"])
        }
        guard bound == 0 else {
            let error = posixError("bind")
            close(fd)
            throw error
        }
        // Owner-only before anyone can connect (listen hasn't been called yet).
        guard chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0,
              fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else {
            let error = posixError("chmod/listen")
            close(fd)
            unlink(path)
            throw error
        }
        return fd
    }

    /// Nonisolated on purpose: handlers formed in a @MainActor method inherit main-actor
    /// isolation and trap when Dispatch runs them on `acceptQueue`.
    private nonisolated static func makeAcceptSource(_ fd: Int32) -> any DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { acceptPending(on: fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private nonisolated static func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return } // EAGAIN: drained
            // BSD accept() inherits O_NONBLOCK; requests are read blocking with a timeout.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            DispatchQueue.global(qos: .userInitiated).async { handle(client) }
        }
    }

    // MARK: - One connection

    private nonisolated static func handle(_ fd: Int32) {
        guard peerIsCurrentUser(fd) else {
            close(fd)
            return
        }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let line = readLine(fd) else {
            reply(.failure("Empty or oversized request."), to: fd)
            return
        }
        guard let command = try? JSONDecoder().decode(Command.self, from: line) else {
            reply(.failure("Invalid request: not a Tessera command."), to: fd)
            return
        }
        Task { @MainActor in
            let result = await CommandBridge.execute(command)
            DispatchQueue.global(qos: .userInitiated).async { reply(result, to: fd) }
        }
    }

    private nonisolated static func peerIsCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    /// Bytes up to the first newline (or EOF), at most `maxRequestBytes`.
    private nonisolated static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maxRequestBytes {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            data.append(contentsOf: buffer[0..<n])
            if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                return data[data.startIndex..<newline]
            }
        }
        return data.isEmpty || data.count > maxRequestBytes ? nil : data
    }

    private nonisolated static func reply(_ result: CommandResult, to fd: Int32) {
        defer { close(fd) }
        guard var data = try? JSONEncoder().encode(result) else { return }
        data.append(UInt8(ascii: "\n"))
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress?.advanced(by: offset), raw.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { return }
                offset += n
            }
        }
    }

    private nonisolated static func posixError(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}

/// Calls `body` with a `sockaddr_un` for `path`; nil if the path doesn't fit in `sun_path`.
private func withUnixAddress<R>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R? {
    var addr = sockaddr_un()
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}
