// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundMeasurement",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "WoundMeasurement", targets: ["WoundMeasurement"]),
    ],
    dependencies: [
        .package(path: "../WoundCore"),
    ],
    targets: [
        .target(
            name: "WoundMeasurement",
            dependencies: [
                .product(name: "WoundCore", package: "WoundCore"),
            ],
            path: "Sources/WoundMeasurement"
        ),
        .testTarget(
            name: "WoundMeasurementTests",
            dependencies: [
                "WoundMeasurement",
                .product(name: "WoundCore", package: "WoundCore"),
            ],
            path: "Tests/WoundMeasurementTests"
        ),
    ]
)
