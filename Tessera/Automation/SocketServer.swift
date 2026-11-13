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
    /// Device and inode of the socket file this instance bound, so `stop()` never removes a successor's socket.
    private var boundFile: (dev: dev_t, ino: ino_t)?
    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "socket")
    private nonisolated static let acceptQueue = DispatchQueue(label: "com.prabeshbhetwal.Tessera.socket")
    private nonisolated static let connectionQueue = DispatchQueue(
        label: "com.prabeshbhetwal.Tessera.socket.connection", qos: .userInitiated, attributes: .concurrent)
    private nonisolated static let maxRequestBytes = 64 * 1024
    private nonisolated static let maxConnections = 8
    private nonisolated static let readDeadline: TimeInterval = 5
    private nonisolated static let inFlight = OSAllocatedUnfairLock(initialState: 0)

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
        var info = stat()
        boundFile = lstat(url.path, &info) == 0 ? (info.st_dev, info.st_ino) : nil
        source = Self.makeAcceptSource(fd)
    }

    func stop() {
        // Only the instance that is listening owns the socket file; a second launch quitting must not remove it.
        guard let source else { return }
        source.cancel()
        self.source = nil
        // Unlink only the file this instance bound; a successor may have replaced it since.
        var info = stat()
        if let url, let boundFile, lstat(url.path, &info) == 0,
           info.st_dev == boundFile.dev, info.st_ino == boundFile.ino {
            unlink(url.path)
        }
        boundFile = nil
    }

    // MARK: - Listening

    private nonisolated static func listen(at url: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = url.path
        guard !hasLiveListener(at: path) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE),
                          userInfo: [NSLocalizedDescriptionKey: "another process is already listening at \(path)"])
        }
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

    /// True when something accepts a connection at `path`; a stale socket file refuses.
    private nonisolated static func hasLiveListener(at path: String) -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        return withUnixAddress(path) { connect(probe, $0, $1) } == 0
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
            // Bounded: each connection holds a worker until it is answered, so refuse extras outright.
            let admitted = inFlight.withLock { count in
                guard count < maxConnections else { return false }
                count += 1
                return true
            }
            guard admitted else {
                // No slot was taken, so none is freed. A short line fits the socket buffer, so this never blocks.
                writeLine(.failure("Tessera is busy. Try again."), to: client)
                close(client)
                continue
            }
            // BSD accept() inherits O_NONBLOCK; requests are read blocking with a timeout.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            connectionQueue.async { handle(client) }
        }
    }

    // MARK: - One connection

    /// Closes an admitted connection and frees its slot.
    private nonisolated static func finish(_ fd: Int32) {
        close(fd)
        inFlight.withLock { $0 -= 1 }
    }

    private nonisolated static func handle(_ fd: Int32) {
        guard peerIsCurrentUser(fd) else {
            finish(fd)
            return
        }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        guard let line = readLine(fd, deadline: Date(timeIntervalSinceNow: readDeadline)) else {
            reply(.failure("Empty, incomplete or oversized request."), to: fd)
            return
        }
        guard let command = try? JSONDecoder().decode(Command.self, from: line) else {
            reply(.failure("Invalid request: not a Tessera command."), to: fd)
            return
        }
        Task { @MainActor in
            let result = await CommandBridge.execute(command)
            connectionQueue.async { reply(result, to: fd) }
        }
    }

    private nonisolated static func peerIsCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    /// Bytes up to the first newline (or EOF), at most `maxRequestBytes`, all arriving before `deadline`.
    private nonisolated static func readLine(_ fd: Int32, deadline: Date) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maxRequestBytes {
            // Shrink the per-read timeout to what is left, so a slow trickle cannot outlast the deadline.
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            let micros = Int(remaining * 1_000_000)
            var timeout = timeval(tv_sec: micros / 1_000_000, tv_usec: Int32(max(micros % 1_000_000, 1)))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n >= 0 else { return nil }
            guard n > 0 else { break }
            data.append(contentsOf: buffer[0..<n])
            if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                guard newline <= maxRequestBytes else { return nil }
                return data[data.startIndex..<newline]
            }
        }
        return data.isEmpty || data.count > maxRequestBytes ? nil : data
    }

    private nonisolated static func reply(_ result: CommandResult, to fd: Int32) {
        defer { finish(fd) }
        writeLine(result, to: fd)
    }

    /// `result` as one JSON line; best effort, the caller closes `fd`.
    private nonisolated static func writeLine(_ result: CommandResult, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(result) else { return }
        data.append(UInt8(ascii: "\n"))
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                // MSG_NOSIGNAL as well as SO_NOSIGPIPE: setting the option fails on a peer that already hung up.
                let n = send(fd, raw.baseAddress?.advanced(by: offset), raw.count - offset, MSG_NOSIGNAL)
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
