import Foundation
import simd
import UIKit
import WoundCore

/// Mock capture provider for unit testing coordinators and view models.
/// Provides a synthetic flat mesh without needing ARKit hardware.
final class MockCaptureProvider: CaptureProviderProtocol {

    var isLiDARAvailable: Bool = true
    var isSessionActive: Bool = false
    var onTrackingStateChanged: ((TrackingState) -> Void)?

    var startSessionCalled = false
    var pauseSessionCalled = false
    var captureSnapshotCalled = false

    var stubbedSnapshot: CaptureSnapshot?
    var stubbedError: Error?

    func startSession() throws {
        startSessionCalled = true
        isSessionActive = true
        if let error = stubbedError { throw error }
    }

    func pauseSession() {
        pauseSessionCalled = true
        isSessionActive = false
    }

    func captureSnapshot() throws -> CaptureSnapshot {
        captureSnapshotCalled = true
        if let error = stubbedError { throw error }
        return stubbedSnapshot ?? Self.syntheticSnapshot()
    }

    /// Builds a synthetic CaptureSnapshot with a 4cm x 4cm flat mesh
    /// for testing without ARKit hardware.
    static func syntheticSnapshot(
        sideMeters: Float = 0.04,
        divisions: Int = 10
    ) -> CaptureSnapshot {
        var vertices = [SIMD3<Float>]()
        var faces = [SIMD3<UInt32>]()
        let step = sideMeters / Float(divisions)
        let half = sideMeters / 2

        for y in 0...divisions {
            for x in 0...divisions {
                vertices.append(SIMD3<Float>(
                    -half + Float(x) * step,
                    -half + Float(y) * step,
                    0
                ))
            }
        }

        let stride = divisions + 1
        for y in 0..<divisions {
            for x in 0..<divisions {
                let i0 = UInt32(y * stride + x)
                let i1 = UInt32(y * stride + x + 1)
                let i2 = UInt32((y + 1) * stride + x)
                let i3 = UInt32((y + 1) * stride + x + 1)
                faces.append(SIMD3<UInt32>(i0, i1, i2))
                faces.append(SIMD3<UInt32>(i1, i3, i2))
            }
        }

        let normals = [SIMD3<Float>](
            repeating: SIMD3<Float>(0, 0, 1),
            count: vertices.count
        )

        // Create a 1x1 pixel JPEG
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let rgbData = image.jpegData(compressionQuality: 0.5) ?? Data()

        return CaptureSnapshot(
            rgbImageData: rgbData,
            imageWidth: 1920,
            imageHeight: 1440,
            depthMap: [Float](repeating: 0.25, count: 256 * 192),
            depthWidth: 256,
            depthHeight: 192,
            confidenceMap: [UInt8](repeating: 2, count: 256 * 192),
            vertices: vertices,
            faces: faces,
            normals: normals,
            cameraIntrinsics: simd_float3x3(
                SIMD3<Float>(1500, 0, 0),
                SIMD3<Float>(0, 1500, 0),
                SIMD3<Float>(960, 720, 1)
            ),
            cameraTransform: matrix_identity_float4x4,
            deviceModel: "MockDevice"
        )
    }
}
