// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundOS",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "WoundCore", targets: ["WoundCore"]),
        .library(name: "WoundCapture", targets: ["WoundCapture"]),
        .library(name: "WoundBoundary", targets: ["WoundBoundary"]),
        .library(name: "WoundMeasurement", targets: ["WoundMeasurement"]),
        .library(name: "WoundNetworking", targets: ["WoundNetworking"]),
    ],
    targets: [
        // MARK: - Libraries
        .target(
            name: "WoundCore",
            path: "Packages/WoundCore/Sources"
        ),
        .target(
            name: "WoundCapture",
            dependencies: ["WoundCore"],
            path: "Packages/WoundCapture/Sources"
        ),
        .target(
            name: "WoundBoundary",
            dependencies: ["WoundCore"],
            path: "Packages/WoundBoundary/Sources"
        ),
        .target(
            name: "WoundMeasurement",
            dependencies: ["WoundCore"],
            path: "Packages/WoundMeasurement/Sources"
        ),
        .target(
            name: "WoundNetworking",
            dependencies: ["WoundCore"],
            path: "Packages/WoundNetworking/Sources"
        ),

        // MARK: - Tests
        .testTarget(
            name: "WoundCoreTests",
            dependencies: ["WoundCore"],
            path: "Tests/WoundCoreTests"
        ),
        .testTarget(
            name: "WoundMeasurementTests",
            dependencies: ["WoundMeasurement", "WoundCore"],
            path: "Tests/WoundMeasurementTests"
        ),
    ]
)
