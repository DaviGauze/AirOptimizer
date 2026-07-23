// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirOptimizer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AirOptimizer",
            path: "Sources/AirOptimizer"
        ),
        .testTarget(
            name: "AirOptimizerTests",
            dependencies: ["AirOptimizer"],
            path: "Tests/AirOptimizerTests"
        )
    ]
)
