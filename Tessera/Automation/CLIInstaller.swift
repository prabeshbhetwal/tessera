import Foundation

/// Symlinks the bundled `tessera` CLI into `~/.local/bin` (Settings → General → Install CLI).
@MainActor
enum CLIInstaller {
    enum InstallError: LocalizedError {
        case missingBinary(URL)
        case occupied(URL)

        var errorDescription: String? {
            switch self {
            case .missingBinary(let url): "The tessera tool is missing from the app bundle (\(url.path))."
            case .occupied(let url): "\(url.path) already exists and isn't a link Tessera created. Remove it and try again."
            }
        }
    }

    /// The CLI inside the app. `Contents/Helpers`, not `Contents/MacOS`: on a case-insensitive
    /// volume `MacOS/tessera` would be the same file as the app's own `MacOS/Tessera`.
    static var bundledURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tessera")
    }

    /// Where the symlink goes. Show this (and that `~/.local/bin` must be on PATH) in the UI.
    static var linkURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/tessera")
    }

    /// True when `linkURL` is a symlink to this app's bundled CLI.
    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) == bundledURL.path
    }

    /// A link Tessera created points at some build's bundled CLI. Each dev build lives in its own
    /// folder and old ones get deleted, so the target may be another (or a missing) Tessera.app.
    static func isTesseraLink(destination: String) -> Bool {
        destination.hasSuffix("/Tessera.app/Contents/Helpers/tessera")
    }

    /// At launch: repoints an installed link that targets a different build (moved, rebuilt elsewhere
    /// or deleted) at this one. Does nothing if the CLI was never installed or the file isn't ours.
    static func repairIfStale() -> Result<URL, Error>? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path),
              destination != bundledURL.path, isTesseraLink(destination: destination) else { return nil }
        return install()
    }

    /// Creates (or repoints) the symlink. Never replaces a file or link the user put there.
    static func install() -> Result<URL, Error> {
        let fm = FileManager.default
        let link = linkURL
        guard fm.isExecutableFile(atPath: bundledURL.path) else { return .failure(InstallError.missingBinary(bundledURL)) }
        do {
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let destination = try? fm.destinationOfSymbolicLink(atPath: link.path), isTesseraLink(destination: destination) {
                try fm.removeItem(at: link) // our old link, possibly to a moved or deleted build
            } else if (try? fm.attributesOfItem(atPath: link.path)) != nil {
                // Exists (fileExists follows links, so a dangling foreign link needs this check).
                return .failure(InstallError.occupied(link))
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: bundledURL)
            return .success(link)
        } catch {
            return .failure(error)
        }
    }
}
