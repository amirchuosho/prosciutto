// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProsciuttoKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ProsciuttoKit", targets: ["ProsciuttoKit"])],
    targets: [
        .target(name: "ProsciuttoKit"),
        .testTarget(name: "ProsciuttoKitTests", dependencies: ["ProsciuttoKit"]),
    ]
)
