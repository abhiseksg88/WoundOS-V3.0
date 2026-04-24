// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaptureSync",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CaptureSync", targets: ["CaptureSync"]),
    ],
    targets: [
        .target(
            name: "CaptureSync",
            path: "Sources/CaptureSync"
        ),
        .testTarget(
            name: "CaptureSyncTests",
            dependencies: ["CaptureSync"],
            path: "Tests/CaptureSyncTests"
        ),
    ]
)
