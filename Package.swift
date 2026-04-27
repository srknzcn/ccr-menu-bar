// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCRMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CCRMenuBar",
            path: "CCRMenuBar",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CCRMenuBarTests",
            dependencies: ["CCRMenuBar"],
            path: "Tests/CCRMenuBarTests"
        )
    ]
)
