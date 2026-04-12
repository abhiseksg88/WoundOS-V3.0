import Foundation
import simd

// MARK: - Depth Calculator

/// Computes wound depth by fitting a reference plane to the boundary points
/// (the wound rim) and measuring how far each interior mesh vertex
/// falls below that plane.
///
/// The reference plane represents the skin surface at the wound edge.
/// Depth = distance from each interior point below this plane.
public enum DepthCalculator {

    public struct DepthResult {
        /// Maximum depth from rim to deepest point, in mm
        public let maxDepthMm: Double
        /// Mean depth across all interior vertices, in mm
        public let meanDepthMm: Double
        /// The reference plane point (centroid of boundary in world space)
        public let referencePlanePoint: SIMD3<Float>
        /// The reference plane normal (pointing outward from wound)
        public let referencePlaneNormal: SIMD3<Float>
        /// Per-vertex depth values (meters, signed: positive = below plane)
        public let vertexDepths: [Float]
    }

    /// Compute depth from boundary points and interior mesh vertices.
    /// - Parameters:
    ///   - boundaryPoints3D: 3D boundary points (wound rim on the mesh surface)
    ///   - interiorVertices: All mesh vertices inside the wound boundary
    ///   - cameraPosition: Camera position to orient the plane normal outward
    /// - Returns: DepthResult with max and mean depth
    public static func computeDepth(
        boundaryPoints3D: [SIMD3<Float>],
        interiorVertices: [SIMD3<Float>],
        cameraPosition: SIMD3<Float>
    ) -> DepthResult? {
        // Fit reference plane to boundary (wound rim)
        guard let plane = TriangleUtils.fitPlane(to: boundaryPoints3D) else {
            return nil
        }

        var planeNormal = plane.normal

        // Orient normal to point toward the camera (outward from wound)
        let toCamera = cameraPosition - plane.point
        if simd_dot(planeNormal, toCamera) < 0 {
            planeNormal = -planeNormal
        }

        // Compute signed distance of each interior vertex from the reference plane.
        // Negative distance = below the plane = wound depth.
        var depths = [Float]()
        depths.reserveCapacity(interiorVertices.count)

        for vertex in interiorVertices {
            let signedDist = TriangleUtils.signedDistanceToPlane(
                point: vertex,
                planePoint: plane.point,
                planeNormal: planeNormal
            )
            // Positive depth means below the reference plane (into the wound)
            depths.append(-signedDist)
        }

        // Only consider positive depths (below the rim plane)
        let positiveDepths = depths.filter { $0 > 0 }

        let maxDepthM = positiveDepths.max() ?? 0
        let meanDepthM: Float
        if positiveDepths.isEmpty {
            meanDepthM = 0
        } else {
            meanDepthM = positiveDepths.reduce(0, +) / Float(positiveDepths.count)
        }

        return DepthResult(
            maxDepthMm: Double(maxDepthM) * 1000.0,  // meters to mm
            meanDepthMm: Double(meanDepthM) * 1000.0,
            referencePlanePoint: plane.point,
            referencePlaneNormal: planeNormal,
            vertexDepths: depths
        )
    }
}
