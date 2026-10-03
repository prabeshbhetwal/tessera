import Darwin
import Foundation
import TesseraCore

// `tessera` CLI (M2 spec §5): argv → Command JSON over the app's Unix socket → CommandResult.
// Exit codes: 0 ok, 1 command error, 2 usage error, 3 app not running.

enum Exit: Int32 { case ok = 0, commandError = 1, usage = 2, notRunning = 3 }

func fail(_ message: String, _ code: Exit) -> Never {
    FileHandle.standardError.write(Data("tessera: \(message)\n".utf8))
    exit(code.rawValue)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let wantsJSON = arguments.contains("--json")

if arguments.isEmpty {
    FileHandle.standardError.write(Data((CommandParser.usage + "\n").utf8))
    exit(Exit.usage.rawValue)
}
if ["-h", "--help", "help"].contains(arguments[0]) {
    print(CommandParser.usage)
    exit(Exit.ok.rawValue)
}

var command: Command
do {
    command = try CommandParser.parse(arguments: arguments)
} catch {
    fail("\(error.localizedDescription)\n\(CommandParser.usage)", .usage)
}

// The app has a different working directory: resolve settings paths here.
func absolute(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        .standardizedFileURL.path
}
switch command {
case .exportSettings(let path): command = .exportSettings(path: absolute(path))
case .importSettings(let path): command = .importSettings(path: absolute(path))
default: break
}

// MARK: Socket round trip

guard let socketPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
    .appendingPathComponent("Tessera/tessera.sock").path else {
    fail("no Application Support directory", .notRunning)
}

func connectToApp(_ path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var addr = sockaddr_un()
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { close(fd); return nil }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 60, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    return fd
}

func send(_ data: Data, to fd: Int32) -> Bool {
    data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let n = write(fd, raw.baseAddress?.advanced(by: offset), raw.count - offset)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
}

func receiveLine(from fd: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        if n < 0, errno == EINTR { continue }
        guard n > 0 else { return data }
        data.append(contentsOf: buffer[0..<n])
        if let newline = data.firstIndex(of: UInt8(ascii: "\n")) { return data[data.startIndex..<newline] }
    }
}

guard let fd = connectToApp(socketPath) else { fail("Tessera isn't running. Open Tessera.app and try again.", .notRunning) }
guard var request = try? JSONEncoder().encode(command) else { fail("couldn't encode the command", .commandError) }
request.append(UInt8(ascii: "\n"))
guard send(request, to: fd) else { close(fd); fail("lost the connection to Tessera", .notRunning) }
let line = receiveLine(from: fd)
close(fd)
guard let result = try? JSONDecoder().decode(CommandResult.self, from: line) else {
    fail("no valid response from Tessera", .commandError)
}

// MARK: Output

func describe(_ r: CGRect) -> String {
    "\(Int(r.width))x\(Int(r.height)) at (\(Int(r.minX)), \(Int(r.minY)))"
}

if wantsJSON {
    print(String(decoding: line, as: UTF8.self))
} else if result.ok {
    for d in result.displays ?? [] {
        print("\(d.index)  \(d.name ?? "Display")  id:\(d.id)  \(describe(d.frame))  "
            + "\(d.columns) columns (\(d.minColumns)–\(d.maxColumns))")
    }
    if let w = result.window {
        let app = [w.app, w.bundleID.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        print("\(app.isEmpty ? "Window" : app)  \(describe(w.frame))  display \(w.displayIndex.map(String.init) ?? "?")")
    }
    if let message = result.message { print(message) }
}
if !result.ok {
    if !wantsJSON { fail(result.message ?? "command failed", .commandError) }
    exit(Exit.commandError.rawValue)
}
exit(Exit.ok.rawValue)
