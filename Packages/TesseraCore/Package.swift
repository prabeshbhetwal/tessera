// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TesseraCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TesseraCore", targets: ["TesseraCore"]),
        .executable(name: "tessera", targets: ["TesseraCLI"]),
    ],
    targets: [
        .target(name: "TesseraCore"),
        .executableTarget(name: "TesseraCLI", dependencies: ["TesseraCore"]),
        .testTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"]),
    ]
)
