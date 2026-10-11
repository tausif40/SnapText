// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CopyText",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CopyText",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "CopyTextTests",
            dependencies: ["CopyText"]
        ),
    ]
)
