// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CappellaMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CappellaMac", targets: ["CappellaMac"])],
    targets: [
        .target(name: "CappellaCore"),
        .target(name: "CappellaSession", dependencies: ["CappellaCore"]),
        .executableTarget(
            name: "CappellaMac",
            dependencies: ["CappellaCore", "CappellaSession"],
            linkerSettings: [.linkedFramework("AVKit")]
        ),
        .testTarget(name: "CappellaCoreTests", dependencies: ["CappellaCore"]),
        .testTarget(name: "CappellaSessionTests", dependencies: ["CappellaCore", "CappellaSession"])
    ]
)
