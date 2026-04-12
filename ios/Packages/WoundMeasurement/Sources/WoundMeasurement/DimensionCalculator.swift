import Foundation
import simd

// MARK: - Dimension Calculator

/// Computes wound length and width using rotating calipers on
/// the convex hull of the projected 3D boundary points.
/// Length = greatest distance across the wound.
/// Width = greatest distance perpendicular to the length axis.
public enum DimensionCalculator {

    public struct DimensionResult {
        /// Greatest distance across the wound in mm
        public let lengthMm: Double
        /// Greatest perpendicular distance in mm
        public let widthMm: Double
        /// Endpoints of the length axis in 3D world space
        public let lengthEndpoints: (SIMD3<Float>, SIMD3<Float>)
        /// Endpoints of the width axis in 3D world space
        public let widthEndpoints: (SIMD3<Float>, SIMD3<Float>)
    }

    /// Compute length and width from 3D boundary points.
    /// Uses the rotating calipers algorithm on the 2D projection
    /// for axis finding, then measures actual 3D distances.
    public static func computeDimensions(
        boundaryPoints3D: [SIMD3<Float>],
        referencePlanePoint: SIMD3<Float>,
        referencePlaneNormal: SIMD3<Float>
    ) -> DimensionResult {
        guard boundaryPoints3D.count >= 3 else {
            return DimensionResult(
                lengthMm: 0, widthMm: 0,
                lengthEndpoints: (.zero, .zero),
                widthEndpoints: (.zero, .zero)
            )
        }

        // Project boundary points onto the reference plane for 2D analysis
        let (projectedPoints2D, planeU, planeV) = projectToPlane(
            boundaryPoints3D,
            planePoint: referencePlanePoint,
            planeNormal: referencePlaneNormal
        )

        // Find the minimum bounding rectangle using rotating calipers
        let hull2D = ProjectionUtils.convexHull(projectedPoints2D)
        guard hull2D.count >= 3 else {
            // Fallback: simple max distance
            return simpleDimensions(boundaryPoints3D)
        }

        let (minRect, minRectAngle) = minimumBoundingRectangle(hull: hull2D)

        // Length = longer side, Width = shorter side
        let side1 = simd_distance(minRect.0, minRect.1)
        let side2 = simd_distance(minRect.1, minRect.2)

        let lengthM: Float
        let widthM: Float
        let lengthDir2D: SIMD2<Float>
        let widthDir2D: SIMD2<Float>

        if side1 >= side2 {
            lengthM = side1
            widthM = side2
            lengthDir2D = simd_normalize(minRect.1 - minRect.0)
            widthDir2D = simd_normalize(minRect.2 - minRect.1)
        } else {
            lengthM = side2
            widthM = side1
            lengthDir2D = simd_normalize(minRect.2 - minRect.1)
            widthDir2D = simd_normalize(minRect.1 - minRect.0)
        }

        // Convert 2D plane directions back to 3D world directions
        let lengthDir3D = lengthDir2D.x * planeU + lengthDir2D.y * planeV
        let widthDir3D = widthDir2D.x * planeU + widthDir2D.y * planeV

        // Find actual 3D length endpoints (most extreme boundary points along length axis)
        let (lEnd1, lEnd2) = extremePointsAlongDirection(boundaryPoints3D, direction: lengthDir3D)
        let (wEnd1, wEnd2) = extremePointsAlongDirection(boundaryPoints3D, direction: widthDir3D)

        return DimensionResult(
            lengthMm: Double(lengthM) * 1000.0,
            widthMm: Double(widthM) * 1000.0,
            lengthEndpoints: (lEnd1, lEnd2),
            widthEndpoints: (wEnd1, wEnd2)
        )
    }

    // MARK: - Project to Plane

    /// Project 3D points onto a plane and return 2D coordinates in the plane's basis.
    private static func projectToPlane(
        _ points: [SIMD3<Float>],
        planePoint: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> ([SIMD2<Float>], SIMD3<Float>, SIMD3<Float>) {
        // Create an orthonormal basis on the plane
        let arbitrary: SIMD3<Float> = abs(planeNormal.x) < 0.9
            ? SIMD3<Float>(1, 0, 0)
            : SIMD3<Float>(0, 1, 0)

        let u = simd_normalize(simd_cross(planeNormal, arbitrary))
        let v = simd_cross(planeNormal, u)

        let projected = points.map { point -> SIMD2<Float> in
            let d = point - planePoint
            return SIMD2<Float>(simd_dot(d, u), simd_dot(d, v))
        }

        return (projected, u, v)
    }

    // MARK: - Minimum Bounding Rectangle

    /// Compute the minimum-area bounding rectangle of a convex hull
    /// using the rotating calipers approach.
    private static func minimumBoundingRectangle(
        hull: [SIMD2<Float>]
    ) -> ((SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>), Float) {
        let n = hull.count
        guard n >= 3 else {
            return ((.zero, .zero, .zero, .zero), 0)
        }

        var minArea: Float = .greatestFiniteMagnitude
        var bestRect = (SIMD2<Float>.zero, SIMD2<Float>.zero, SIMD2<Float>.zero, SIMD2<Float>.zero)
        var bestAngle: Float = 0

        // For each edge of the convex hull, compute the bounding rectangle
        // aligned to that edge.
        for i in 0..<n {
            let j = (i + 1) % n
            let edge = hull[j] - hull[i]
            let angle = atan2(edge.y, edge.x)

            let cosA = cos(-angle)
            let sinA = sin(-angle)

            // Rotate all hull points by -angle
            var minX: Float = .greatestFiniteMagnitude
            var maxX: Float = -.greatestFiniteMagnitude
            var minY: Float = .greatestFiniteMagnitude
            var maxY: Float = -.greatestFiniteMagnitude

            for p in hull {
                let rx = p.x * cosA - p.y * sinA
                let ry = p.x * sinA + p.y * cosA
                minX = min(minX, rx)
                maxX = max(maxX, rx)
                minY = min(minY, ry)
                maxY = max(maxY, ry)
            }

            let area = (maxX - minX) * (maxY - minY)

            if area < minArea {
                minArea = area

                // Rotate the rectangle corners back
                let cosAngle = cos(angle)
                let sinAngle = sin(angle)

                func rotate(_ x: Float, _ y: Float) -> SIMD2<Float> {
                    SIMD2<Float>(
                        x * cosAngle - y * sinAngle,
                        x * sinAngle + y * cosAngle
                    )
                }

                bestRect = (
                    rotate(minX, minY),
                    rotate(maxX, minY),
                    rotate(maxX, maxY),
                    rotate(minX, maxY)
                )
                bestAngle = angle
            }
        }

        return (bestRect, bestAngle)
    }

    // MARK: - Extreme Points

    /// Find the two boundary points most extreme along a direction.
    private static func extremePointsAlongDirection(
        _ points: [SIMD3<Float>],
        direction: SIMD3<Float>
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        var minProj: Float = .greatestFiniteMagnitude
        var maxProj: Float = -.greatestFiniteMagnitude
        var minPoint = points[0]
        var maxPoint = points[0]

        for p in points {
            let proj = simd_dot(p, direction)
            if proj < minProj {
                minProj = proj
                minPoint = p
            }
            if proj > maxProj {
                maxProj = proj
                maxPoint = p
            }
        }

        return (minPoint, maxPoint)
    }

    // MARK: - Fallback

    /// Simple diameter-based dimension computation when convex hull fails.
    private static func simpleDimensions(_ points: [SIMD3<Float>]) -> DimensionResult {
        var maxDist: Float = 0
        var p1 = points[0], p2 = points[0]

        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let d = simd_distance(points[i], points[j])
                if d > maxDist {
                    maxDist = d
                    p1 = points[i]
                    p2 = points[j]
                }
            }
        }

        // Width as approximate perpendicular extent
        let lengthDir = simd_normalize(p2 - p1)
        var maxPerp: Float = 0
        var w1 = points[0], w2 = points[0]

        for point in points {
            let proj = simd_dot(point - p1, lengthDir)
            let projPoint = p1 + proj * lengthDir
            let perpDist = simd_distance(point, projPoint)
            if perpDist > maxPerp {
                maxPerp = perpDist
                w1 = projPoint
                w2 = point
            }
        }

        return DimensionResult(
            lengthMm: Double(maxDist) * 1000.0,
            widthMm: Double(maxPerp) * 1000.0 * 2.0,
            lengthEndpoints: (p1, p2),
            widthEndpoints: (w1, w2)
        )
    }
}
