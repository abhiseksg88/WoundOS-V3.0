import Foundation
import simd

// MARK: - Projection Utilities

/// Coordinate system transformations between image space, camera space,
/// and world space.
public enum ProjectionUtils {

    /// Convert normalized image coordinates (0...1) to pixel coordinates.
    public static func normalizedToPixel(
        _ normalized: SIMD2<Float>,
        imageWidth: Int,
        imageHeight: Int
    ) -> SIMD2<Float> {
        SIMD2<Float>(
            normalized.x * Float(imageWidth),
            normalized.y * Float(imageHeight)
        )
    }

    /// Convert pixel coordinates to normalized image coordinates (0...1).
    public static func pixelToNormalized(
        _ pixel: SIMD2<Float>,
        imageWidth: Int,
        imageHeight: Int
    ) -> SIMD2<Float> {
        SIMD2<Float>(
            pixel.x / Float(imageWidth),
            pixel.y / Float(imageHeight)
        )
    }

    /// Convert pixel coordinates to a camera-space ray direction.
    /// The ray originates at the camera and passes through the pixel.
    public static func pixelToRay(
        pixel: SIMD2<Float>,
        intrinsics: simd_float3x3
    ) -> SIMD3<Float> {
        let invIntrinsics = intrinsics.inverse
        let homogeneous = SIMD3<Float>(pixel.x, pixel.y, 1.0)
        return simd_normalize(invIntrinsics * homogeneous)
    }

    /// Project a 3D world point to normalized image coordinates.
    /// Returns nil if the point is behind the camera.
    public static func worldToNormalized(
        _ worldPoint: SIMD3<Float>,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) -> SIMD2<Float>? {
        let viewMatrix = cameraTransform.inverse
        let camPoint4 = viewMatrix * SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)
        let camPoint = SIMD3<Float>(camPoint4.x, camPoint4.y, camPoint4.z)

        // Behind camera
        guard camPoint.z > 0 else { return nil }

        let projected = intrinsics * camPoint
        return SIMD2<Float>(
            projected.x / (projected.z * Float(imageWidth)),
            projected.y / (projected.z * Float(imageHeight))
        )
    }

    /// Unproject a depth value at a pixel to a 3D camera-space point.
    public static func unprojectPixel(
        pixel: SIMD2<Float>,
        depth: Float,
        intrinsics: simd_float3x3
    ) -> SIMD3<Float> {
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        return SIMD3<Float>(
            (pixel.x - cx) * depth / fx,
            (pixel.y - cy) * depth / fy,
            depth
        )
    }

    // MARK: - Polygon Ordering

    /// Reorder 2D points into counter-clockwise winding around their centroid.
    /// Eliminates self-intersections caused by arbitrary point ordering
    /// (e.g. from mask contour extraction or shuffled segmentation output).
    public static func orderPointsCounterClockwise(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }

        // Compute centroid
        var cx: Float = 0, cy: Float = 0
        for p in points {
            cx += p.x
            cy += p.y
        }
        cx /= Float(points.count)
        cy /= Float(points.count)

        // Sort by angle around centroid (counter-clockwise)
        return points.sorted { a, b in
            let angleA = atan2(a.y - cy, a.x - cx)
            let angleB = atan2(b.y - cy, b.x - cx)
            return angleA < angleB
        }
    }

    /// Compute the signed area of a 2D polygon using the shoelace formula.
    /// Returns the absolute area. Used as a diagnostic cross-check against
    /// the mesh-based area computation.
    public static func polygonArea2D(_ points: [SIMD2<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }
        var signedArea: Float = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            signedArea += points[i].x * points[j].y
            signedArea -= points[j].x * points[i].y
        }
        return abs(signedArea) / 2.0
    }

    // MARK: - Convex Hull

    /// Compute the convex hull of a set of 2D points using Graham scan.
    /// Returns points in counter-clockwise order.
    public static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }

        // Find the bottom-most point (and leftmost if tie)
        var sorted = points
        let pivot = sorted.min(by: { a, b in
            a.y < b.y || (a.y == b.y && a.x < b.x)
        })!

        // Sort by polar angle relative to pivot
        sorted.sort { a, b in
            let angleA = atan2(a.y - pivot.y, a.x - pivot.x)
            let angleB = atan2(b.y - pivot.y, b.x - pivot.x)
            if abs(angleA - angleB) < 1e-8 {
                let distA = simd_distance(a, pivot)
                let distB = simd_distance(b, pivot)
                return distA < distB
            }
            return angleA < angleB
        }

        var hull = [SIMD2<Float>]()

        for point in sorted {
            while hull.count >= 2 {
                let a = hull[hull.count - 2]
                let b = hull[hull.count - 1]
                let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                if cross <= 0 {
                    hull.removeLast()
                } else {
                    break
                }
            }
            hull.append(point)
        }

        return hull
    }
}
