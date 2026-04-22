import Foundation
import os
import simd

private let logger = Logger(subsystem: "com.woundos.app", category: "Depth")

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
        /// Number of interior vertices below the reference plane
        public let belowPlaneCount: Int
        /// Number of interior vertices above the reference plane
        public let abovePlaneCount: Int
        /// Whether the result is considered reliable
        public let isReliable: Bool
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
        logger.info("computeDepth: boundary=\(boundaryPoints3D.count) pts, interior=\(interiorVertices.count) vertices")

        // Fit reference plane to boundary (wound rim)
        guard let plane = TriangleUtils.fitPlane(to: boundaryPoints3D) else {
            logger.error("Plane fit failed — insufficient boundary points or degenerate geometry")
            return nil
        }

        var planeNormal = plane.normal

        // Orient normal to point toward the camera (outward from wound)
        let toCamera = cameraPosition - plane.point
        if simd_dot(planeNormal, toCamera) < 0 {
            planeNormal = -planeNormal
        }

        logger.info("Plane: center=(\(plane.point.x), \(plane.point.y), \(plane.point.z)) normal=(\(planeNormal.x), \(planeNormal.y), \(planeNormal.z))")

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
        let negativeDepths = depths.filter { $0 <= 0 }

        let belowCount = positiveDepths.count
        let aboveCount = negativeDepths.count
        let total = depths.count

        let belowPct = total > 0 ? Double(belowCount) / Double(total) * 100.0 : 0
        let abovePct = total > 0 ? Double(aboveCount) / Double(total) * 100.0 : 0

        logger.info("Depth distribution: \(belowCount) below plane (\(belowPct)%), \(aboveCount) above plane (\(abovePct)%)")

        let maxDepthM = positiveDepths.max() ?? 0
        let meanDepthM: Float
        if positiveDepths.isEmpty {
            meanDepthM = 0
        } else {
            meanDepthM = positiveDepths.reduce(0, +) / Float(positiveDepths.count)
        }

        // Reliability check: unreliable if < 10 interior vertices below plane
        // or > 30% of vertices are above the plane (indicating poor plane fit)
        let isReliable = belowCount >= 10 && abovePct <= 30.0

        let maxMm = Double(maxDepthM) * 1000.0
        let meanMm = Double(meanDepthM) * 1000.0
        logger.info("Depth result: max=\(maxMm)mm, mean=\(meanMm)mm, reliable=\(isReliable)")

        if !isReliable {
            logger.warning("Depth UNRELIABLE: belowPlane=\(belowCount) (<10?) abovePct=\(abovePct)% (>30%?)")
        }

        return DepthResult(
            maxDepthMm: Double(maxDepthM) * 1000.0,  // meters to mm
            meanDepthMm: Double(meanDepthM) * 1000.0,
            referencePlanePoint: plane.point,
            referencePlaneNormal: planeNormal,
            vertexDepths: depths,
            belowPlaneCount: belowCount,
            abovePlaneCount: aboveCount,
            isReliable: isReliable
        )
    }
}
