// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundAutoSegmentation",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WoundAutoSegmentation", targets: ["WoundAutoSegmentation"]),
    ],
    dependencies: [
        .package(path: "../WoundCore"),
    ],
    targets: [
        .target(
            name: "WoundAutoSegmentation",
            dependencies: [
                .product(name: "WoundCore", package: "WoundCore"),
            ],
            path: "Sources/WoundAutoSegmentation"
            // Uncomment after running Scripts/convert_fusegnet.py to add the CoreML model:
            // resources: [.copy("Resources/FUSegNet.mlpackage")]
        ),
        .testTarget(
            name: "WoundAutoSegmentationTests",
            dependencies: ["WoundAutoSegmentation"],
            path: "Tests/WoundAutoSegmentationTests"
        ),
    ]
)
