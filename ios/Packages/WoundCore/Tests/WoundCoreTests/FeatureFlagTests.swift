import XCTest
import simd
@testable import WoundCore

// Note: FeatureFlags, FeatureFlag, and FeatureFlagStore are defined
// in the app target (WoundOS/Utilities/FeatureFlags.swift), not in
// WoundCore. These tests verify the InMemoryFlagStore behavior.
// App-target tests would need a host app test target.

final class CaptureDataSnapshotBridgeTests: XCTestCase {

    func testCaptureSnapshot_toCaptureData_roundTrip() {
        let snapshot = CaptureSnapshot(
            rgbImageData: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            imageWidth: 1920,
            imageHeight: 1440,
            depthMap: [0.25, 0.30, 0.22, 0.28],
            depthWidth: 2,
            depthHeight: 2,
            confidenceMap: [2, 1, 2, 0],
            vertices: [
                SIMD3<Float>(0.1, 0.2, 0.3),
                SIMD3<Float>(0.4, 0.5, 0.6),
            ],
            faces: [
                SIMD3<UInt32>(0, 1, 0),
            ],
            normals: [
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(0, 0, 1),
            ],
            cameraIntrinsics: simd_float3x3(
                SIMD3<Float>(1500, 0, 0),
                SIMD3<Float>(0, 1500, 0),
                SIMD3<Float>(960, 720, 1)
            ),
            cameraTransform: matrix_identity_float4x4,
            deviceModel: "TestDevice"
        )

        let captureData = snapshot.toCaptureData(lidarAvailable: true)

        XCTAssertEqual(captureData.imageWidth, 1920)
        XCTAssertEqual(captureData.imageHeight, 1440)
        XCTAssertEqual(captureData.vertexCount, 2)
        XCTAssertEqual(captureData.faceCount, 1)
        XCTAssertEqual(captureData.deviceModel, "TestDevice")
        XCTAssertTrue(captureData.lidarAvailable)
        XCTAssertEqual(captureData.depthWidth, 2)
        XCTAssertEqual(captureData.depthHeight, 2)

        // Verify round-trip
        let restored = captureData.toCaptureSnapshot()
        XCTAssertEqual(restored.imageWidth, snapshot.imageWidth)
        XCTAssertEqual(restored.imageHeight, snapshot.imageHeight)
        XCTAssertEqual(restored.vertices.count, snapshot.vertices.count)
        XCTAssertEqual(restored.faces.count, snapshot.faces.count)
        XCTAssertEqual(restored.normals.count, snapshot.normals.count)
        XCTAssertEqual(restored.depthMap.count, snapshot.depthMap.count)
        XCTAssertEqual(restored.confidenceMap.count, snapshot.confidenceMap.count)
        XCTAssertEqual(restored.deviceModel, snapshot.deviceModel)

        // Verify vertex values survived the round-trip
        XCTAssertEqual(restored.vertices[0].x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(restored.vertices[0].y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(restored.vertices[0].z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(restored.vertices[1].x, 0.4, accuracy: 0.0001)

        // Verify depth survived
        XCTAssertEqual(restored.depthMap[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(restored.depthMap[1], 0.30, accuracy: 0.0001)
    }

    func testCaptureData_toCaptureSnapshot_emptyMesh() {
        let captureData = CaptureData(
            rgbImageData: Data([0xFF]),
            imageWidth: 640,
            imageHeight: 480,
            depthMapData: Data(),
            depthWidth: 0,
            depthHeight: 0,
            confidenceMapData: Data(),
            meshVerticesData: Data(),
            meshFacesData: Data(),
            meshNormalsData: Data(),
            vertexCount: 0,
            faceCount: 0,
            cameraIntrinsics: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            cameraTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            deviceModel: "NoLiDAR",
            lidarAvailable: false
        )

        let snapshot = captureData.toCaptureSnapshot()
        XCTAssertEqual(snapshot.vertices.count, 0)
        XCTAssertEqual(snapshot.faces.count, 0)
        XCTAssertEqual(snapshot.normals.count, 0)
        XCTAssertEqual(snapshot.depthMap.count, 0)
        XCTAssertEqual(snapshot.deviceModel, "NoLiDAR")
    }
}
