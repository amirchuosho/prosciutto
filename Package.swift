// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProsciuttoKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ProsciuttoKit", targets: ["ProsciuttoKit"])],
    targets: [
        .target(name: "ProsciuttoKit", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ProsciuttoKitTests", dependencies: ["ProsciuttoKit"]),
        // Dev/testing CLI around the shared PasteImporter (in ProsciuttoKit). The in-app
        // "Import from Paste…" is the shipping path; this drives the same code from the
        // terminal. `swift run PasteMigrator --dry-run`.
        .executableTarget(name: "PasteMigrator", dependencies: ["ProsciuttoKit"]),
    ]
)
