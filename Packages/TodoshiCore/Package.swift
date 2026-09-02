// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NexusCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NexusCore", targets: ["NexusCore"])
    ],
    targets: [
        .target(
            name: "NexusCore",
            path: "Sources/NexusCore",
            resources: [
                .process("L10n")
            ]
        ),
        .testTarget(
            name: "NexusCoreTests",
            dependencies: ["NexusCore"],
            path: "Tests/NexusCoreTests"
        )
    ]
)
