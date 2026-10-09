// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hotplate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HotplateCore"),
        .target(name: "HotplateTUI", dependencies: ["HotplateCore"]),
        .executableTarget(name: "Hotplate", dependencies: ["HotplateCore"]),
        .executableTarget(name: "hotplate-cli", dependencies: ["HotplateCore", "HotplateTUI"], path: "Sources/hotplate-cli"),
        .target(name: "HotplateTestSupport", dependencies: ["HotplateCore"], path: "Tests/HotplateTestSupport"),
        .testTarget(name: "HotplateCoreTests", dependencies: ["HotplateCore", "HotplateTestSupport"]),
        .testTarget(name: "HotplateTUITests", dependencies: ["HotplateTUI", "HotplateCore", "HotplateTestSupport"]),
    ]
)
