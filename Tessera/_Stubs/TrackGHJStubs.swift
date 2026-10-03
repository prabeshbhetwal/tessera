// TEMPORARY STUB — coordinator deletes at merge
import Foundation

/// Track J signature (`Tessera/Automation/CLIInstaller.swift`).
@MainActor
enum CLIInstaller {
    static var bundledURL: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/tessera") }
    static var linkURL: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/tessera") }
    static var isInstalled: Bool { false }

    static func install() -> Result<URL, Error> {
        .failure(CocoaError(.featureUnsupported))
    }
}
