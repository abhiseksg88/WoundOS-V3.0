// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundBoundary",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "WoundBoundary", targets: ["WoundBoundary"]),
    ],
    dependencies: [
        .package(path: "../WoundCore"),
    ],
    targets: [
        .target(
            name: "WoundBoundary",
            dependencies: [
                .product(name: "WoundCore", package: "WoundCore"),
            ],
            path: "Sources/WoundBoundary"
        ),
    ]
)
