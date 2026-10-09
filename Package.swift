// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hotplate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HotplateCore"),
        .executableTarget(name: "Hotplate", dependencies: ["HotplateCore"]),
        .target(name: "HotplateTestSupport", dependencies: ["HotplateCore"], path: "Tests/HotplateTestSupport"),
        .testTarget(name: "HotplateCoreTests", dependencies: ["HotplateCore", "HotplateTestSupport"]),
    ]
)
