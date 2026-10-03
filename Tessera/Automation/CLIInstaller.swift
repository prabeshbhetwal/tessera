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

    /// The target Tessera last wrote into the link. A path alone can't prove who made a link (the user
    /// may point it at a stable /Applications/Tessera.app themselves), so ownership is this record.
    /// Every build shares the bundle id, hence the same defaults.
    private static let ownedTargetKey = "cliLinkTarget"

    /// True when the link exists and still points where Tessera last put it.
    static var ownsLink: Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path) else { return false }
        return destination == UserDefaults.standard.string(forKey: ownedTargetKey)
    }

    /// A link that targets some build's bundled CLI. Each dev build lives in its own folder and old
    /// ones get deleted, so the target may be another (or a missing) Tessera.app.
    static func isTesseraLink(destination: String) -> Bool {
        destination.hasSuffix("/Tessera.app/Contents/Helpers/tessera")
    }

    /// At launch: a link Tessera wrote that now targets another build (moved, rebuilt elsewhere or
    /// deleted) is repointed at this one. A link pointing here already is adopted (covers links made
    /// before ownership was recorded). Anything else — no link, or one the user made — is left alone.
    static func repairIfStale() -> Result<URL, Error>? {
        if isInstalled {
            UserDefaults.standard.set(bundledURL.path, forKey: ownedTargetKey)
            return nil
        }
        guard ownsLink else { return nil }
        return install()
    }

    /// Creates (or repoints) the symlink. Replaces only a link Tessera owns or one that targets a
    /// Tessera build (an explicit Install may retarget those); never a file or link the user put there.
    static func install() -> Result<URL, Error> {
        let fm = FileManager.default
        let link = linkURL
        guard fm.isExecutableFile(atPath: bundledURL.path) else { return .failure(InstallError.missingBinary(bundledURL)) }
        do {
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let destination = try? fm.destinationOfSymbolicLink(atPath: link.path),
               ownsLink || isTesseraLink(destination: destination) {
                try fm.removeItem(at: link)
            } else if (try? fm.attributesOfItem(atPath: link.path)) != nil {
                // Exists (fileExists follows links, so a dangling foreign link needs this check).
                return .failure(InstallError.occupied(link))
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: bundledURL)
            UserDefaults.standard.set(bundledURL.path, forKey: ownedTargetKey)
            return .success(link)
        } catch {
            return .failure(error)
        }
    }
}
