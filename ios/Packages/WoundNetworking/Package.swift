// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundNetworking",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WoundNetworking", targets: ["WoundNetworking"]),
    ],
    dependencies: [
        .package(path: "../WoundCore"),
    ],
    targets: [
        .target(
            name: "WoundNetworking",
            dependencies: [
                .product(name: "WoundCore", package: "WoundCore"),
            ],
            path: "Sources/WoundNetworking"
        ),
        .testTarget(
            name: "WoundNetworkingTests",
            dependencies: ["WoundNetworking"],
            path: "Tests/WoundNetworkingTests"
        ),
    ]
)
