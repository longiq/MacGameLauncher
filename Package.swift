// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacGameLauncher",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MacGameLauncher",
            path: "Sources/MacGameLauncher"
        )
    ]
)
