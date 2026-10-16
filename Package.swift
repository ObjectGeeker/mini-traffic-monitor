// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MiniTrafficMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MiniTrafficMonitor",
            path: "Sources/MiniTrafficMonitor",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("SystemConfiguration")]
        )
    ]
)
