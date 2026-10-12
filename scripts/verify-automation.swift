import Darwin
import Foundation
import TesseraCore

@MainActor private final class TestExecutor: CommandExecuting {
    var calls = 0
    func execute(_ command: Command) async -> CommandResult {
        calls += 1
        return .success
    }
}

@main private struct VerifyAutomation {
    private struct Failure: Error { let message: String }

    @MainActor static func main() async {
        do {
            try await verify()
            print("PASS: CLI socket framing, 64 KiB boundary, invalid requests and timeout recovery; bridge isolation.")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor private static func verify() async throws {
        let url = URL(fileURLWithPath: "/tmp/tessera-socket-\(UUID().uuidString).sock")
        let executor = TestExecutor()
        CommandBridge.executor = executor
        let server = SocketServer(url: url)
        server.start()
        defer { server.stop(); CommandBridge.executor = nil }

        let command = try JSONEncoder().encode(Command.listDisplays)
        let limit = 64 * 1024
        let cases: [(String, Data, Bool, Bool)] = [
            ("valid", command + Data([10]), true, true),
            ("at limit", command + Data(repeating: 32, count: limit - command.count) + Data([10]), true, true),
            ("over limit with newline", command + Data(repeating: 32, count: limit + 1 - command.count) + Data([10]), false, true),
            ("malformed", Data("not JSON\n".utf8), false, true),
            ("empty", Data(), false, true),
            ("valid EOF", command, true, true),
            ("unterminated timeout", command, false, false)
        ]
        for (name, payload, expected, endRequest) in cases {
            let result = try await Task.detached { try request(payload, path: url.path, endRequest: endRequest) }.value
            guard result.ok == expected else { throw Failure(message: "\(name): expected ok=\(expected), got \(result.ok)") }
            print("PASS: \(name)")
        }
        guard executor.calls == 3 else { throw Failure(message: "Invalid requests reached CommandBridge") }
        var mode = stat()
        guard lstat(url.path, &mode) == 0, mode.st_mode & 0o777 == 0o600 else {
            throw Failure(message: "Socket is not owner-only")
        }
    }

    private static func request(_ payload: Data, path: String, endRequest: Bool) throws -> CommandResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(message: "socket failed") }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        // Let the server's five-second read deadline expire before the fixture client gives up.
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw Failure(message: "Socket path too long") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure(message: "connect failed") }
        try payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress?.advanced(by: offset), raw.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw Failure(message: "write failed") }
                offset += n
            }
        }
        if endRequest { shutdown(fd, SHUT_WR) }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while response.count < 64 * 1024 {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            response.append(contentsOf: buffer.prefix(n))
            if response.contains(10) { break }
        }
        return try JSONDecoder().decode(CommandResult.self, from: response)
    }
}
