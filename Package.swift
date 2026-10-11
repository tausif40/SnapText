// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnapText",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SnapText",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "SnapTextTests",
            dependencies: ["SnapText"]
        ),
    ]
)
