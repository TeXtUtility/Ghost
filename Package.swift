// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ghost",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ghost", targets: ["Ghost"])
    ],
    targets: [
        .executableTarget(
            name: "Ghost",
            path: "Sources/Ghost"
        ),
        .testTarget(
            name: "GhostTests",
            dependencies: ["Ghost"],
            path: "Tests/GhostTests"
        )
    ]
)
