// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCRMenuBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "CCRMenuBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
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
