// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundCapture",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "WoundCapture", targets: ["WoundCapture"]),
    ],
    dependencies: [
        .package(path: "../WoundCore"),
    ],
    targets: [
        .target(
            name: "WoundCapture",
            dependencies: [
                .product(name: "WoundCore", package: "WoundCore"),
            ],
            path: "Sources/WoundCapture"
        ),
    ]
)
