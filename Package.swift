// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Offshoot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Offshoot", path: "Sources/Offshoot"),
        .testTarget(name: "OffshootTests", dependencies: ["Offshoot"], path: "Tests/OffshootTests"),
    ]
)
