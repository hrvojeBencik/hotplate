// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hotplate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HotplateCore"),
        .executableTarget(name: "Hotplate", dependencies: ["HotplateCore"]),
        .testTarget(name: "HotplateCoreTests", dependencies: ["HotplateCore"]),
    ]
)
