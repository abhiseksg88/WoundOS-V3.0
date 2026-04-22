// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundCore",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "WoundCore", targets: ["WoundCore"]),
    ],
    targets: [
        .target(
            name: "WoundCore",
            path: "Sources/WoundCore"
        ),
        .testTarget(
            name: "WoundCoreTests",
            dependencies: ["WoundCore"],
            path: "Tests/WoundCoreTests"
        ),
    ]
)
