import Foundation
import simd

// MARK: - Measurement Engine Protocol

/// Contract for computing wound measurements from a boundary
/// projected onto frozen ARKit mesh data. All implementations
/// must be deterministic given the same inputs.
///
/// Camera intrinsics + transform are required so the rigorous
/// MeshClipper can project 3D mesh vertices to image space for
/// the boundary-containment test.
public protocol MeasurementEngineProtocol {

    func computeMeasurements(
        boundary: WoundBoundary,
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        cameraIntrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int,
        qualityScore: CaptureQualityScore?
    ) throws -> WoundMeasurement
}

// MARK: - Measurement Errors

public enum MeasurementError: Error, LocalizedError {
    case insufficientBoundaryPoints(count: Int, minimum: Int)
    case projectionFailed(reason: String)
    case meshClippingFailed(reason: String)
    case degenerateBoundary
    case noMeshIntersection
    case computationTimeout

    public var errorDescription: String? {
        switch self {
        case .insufficientBoundaryPoints(let count, let minimum):
            return "Boundary has \(count) points, minimum \(minimum) required"
        case .projectionFailed(let reason):
            return "2D→3D projection failed: \(reason)"
        case .meshClippingFailed(let reason):
            return "Mesh clipping failed: \(reason)"
        case .degenerateBoundary:
            return "Boundary is degenerate (self-intersecting or zero area)"
        case .noMeshIntersection:
            return "No mesh triangles found within wound boundary"
        case .computationTimeout:
            return "Measurement computation timed out"
        }
    }
}
