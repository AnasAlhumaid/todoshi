// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TodoshiCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TodoshiCore", targets: ["TodoshiCore"])
    ],
    targets: [
        .target(
            name: "TodoshiCore",
            path: "Sources/TodoshiCore",
            resources: [
                .process("L10n")
            ]
        ),
        .testTarget(
            name: "TodoshiCoreTests",
            dependencies: ["TodoshiCore"],
            path: "Tests/TodoshiCoreTests"
        )
    ]
)
