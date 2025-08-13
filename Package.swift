// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeAuth",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "ClaudeAuth",
            targets: ["ClaudeAuth"]
        ),
        .executable(
            name: "claude-auth-test",
            targets: ["ClaudeAuthCLI"]
        ),
    ],
    dependencies: [
        // No external dependencies - using native Swift/Apple frameworks only
    ],
    targets: [
        .target(
            name: "ClaudeAuth",
            dependencies: [],
            path: "Sources/ClaudeAuth"
        ),
        .executableTarget(
            name: "ClaudeAuthCLI",
            dependencies: ["ClaudeAuth"],
            path: "Sources/ClaudeAuthCLI"
        ),
        .testTarget(
            name: "ClaudeAuthTests",
            dependencies: ["ClaudeAuth"],
            path: "Tests/ClaudeAuthTests"
        ),
    ]
)