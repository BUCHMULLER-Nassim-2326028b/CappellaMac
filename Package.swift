// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CappellaMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CappellaMac", targets: ["CappellaMac"])],
    targets: [
        .target(name: "CappellaCore"),
        .executableTarget(name: "CappellaMac", dependencies: ["CappellaCore"]),
        .testTarget(name: "CappellaCoreTests", dependencies: ["CappellaCore"])
    ]
)
