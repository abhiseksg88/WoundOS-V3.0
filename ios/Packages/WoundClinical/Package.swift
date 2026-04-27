// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WoundClinical",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WoundClinical", targets: ["WoundClinical"]),
    ],
    dependencies: [
        .package(path: "../WoundCore"),
    ],
    targets: [
        .target(
            name: "WoundClinical",
            dependencies: ["WoundCore"]
        ),
        .testTarget(
            name: "WoundClinicalTests",
            dependencies: ["WoundClinical"]
        ),
    ]
)
