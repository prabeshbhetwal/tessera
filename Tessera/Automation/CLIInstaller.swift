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

    /// Creates (or repoints) the symlink. Never replaces a regular file the user put there.
    static func install() -> Result<URL, Error> {
        let fm = FileManager.default
        let link = linkURL
        guard fm.isExecutableFile(atPath: bundledURL.path) else { return .failure(InstallError.missingBinary(bundledURL)) }
        do {
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try fm.removeItem(at: link) // our old link, possibly to a moved app
            } else if fm.fileExists(atPath: link.path) {
                return .failure(InstallError.occupied(link))
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: bundledURL)
            return .success(link)
        } catch {
            return .failure(error)
        }
    }
}
