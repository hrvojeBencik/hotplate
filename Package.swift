// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlutterRunner",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlutterRunnerCore"),
        .executableTarget(name: "FlutterRunner", dependencies: ["FlutterRunnerCore"]),
        .testTarget(name: "FlutterRunnerCoreTests", dependencies: ["FlutterRunnerCore"]),
    ]
)
