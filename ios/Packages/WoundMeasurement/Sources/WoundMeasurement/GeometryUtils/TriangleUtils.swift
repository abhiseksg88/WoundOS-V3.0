import Foundation
import simd

// MARK: - Triangle Utilities

/// Pure geometry operations on triangles and polygons.
public enum TriangleUtils {

    /// Area of a 3D triangle defined by three vertices.
    /// Uses half the magnitude of the cross product.
    public static func triangleArea(
        _ v0: SIMD3<Float>,
        _ v1: SIMD3<Float>,
        _ v2: SIMD3<Float>
    ) -> Float {
        let cross = simd_cross(v1 - v0, v2 - v0)
        return simd_length(cross) * 0.5
    }

    /// Normal vector of a triangle (not normalized).
    public static func triangleNormal(
        _ v0: SIMD3<Float>,
        _ v1: SIMD3<Float>,
        _ v2: SIMD3<Float>
    ) -> SIMD3<Float> {
        simd_cross(v1 - v0, v2 - v0)
    }

    /// Centroid of a triangle.
    public static func triangleCentroid(
        _ v0: SIMD3<Float>,
        _ v1: SIMD3<Float>,
        _ v2: SIMD3<Float>
    ) -> SIMD3<Float> {
        (v0 + v1 + v2) / 3.0
    }

    /// Signed volume of a tetrahedron formed by a triangle and the origin.
    /// V = (1/6) * v0 · (v1 × v2)
    public static func signedTetrahedronVolume(
        _ v0: SIMD3<Float>,
        _ v1: SIMD3<Float>,
        _ v2: SIMD3<Float>
    ) -> Float {
        simd_dot(v0, simd_cross(v1, v2)) / 6.0
    }

    /// Centroid (center of mass) of a 3D polygon defined by ordered points.
    public static func polygonCentroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(SIMD3<Float>.zero, +)
        return sum / Float(points.count)
    }

    /// Fit a least-squares plane to a set of 3D points.
    /// Returns (planePoint, planeNormal) where planeNormal is the unit normal.
    /// Uses SVD via the covariance matrix to find the plane of best fit.
    public static func fitPlane(to points: [SIMD3<Float>]) -> (point: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard points.count >= 3 else { return nil }

        // Compute centroid
        let centroid = polygonCentroid(points)

        // Build covariance matrix
        var xx: Float = 0, xy: Float = 0, xz: Float = 0
        var yy: Float = 0, yz: Float = 0
        var zz: Float = 0

        for p in points {
            let d = p - centroid
            xx += d.x * d.x
            xy += d.x * d.y
            xz += d.x * d.z
            yy += d.y * d.y
            yz += d.y * d.z
            zz += d.z * d.z
        }

        let n = Float(points.count)
        xx /= n; xy /= n; xz /= n; yy /= n; yz /= n; zz /= n

        // The normal is the eigenvector corresponding to the smallest eigenvalue
        // of the covariance matrix. We find it using the characteristic equation
        // and power iteration on the minor axis.
        // For robustness, try each axis and pick the one with smallest variance.

        let det_x = yy * zz - yz * yz
        let det_y = xx * zz - xz * xz
        let det_z = xx * yy - xy * xy

        // Choose the axis with the largest determinant (most stable normal computation)
        var normal: SIMD3<Float>

        if det_x >= det_y && det_x >= det_z {
            normal = SIMD3<Float>(det_x, xz * yz - xy * zz, xy * yz - xz * yy)
        } else if det_y >= det_x && det_y >= det_z {
            normal = SIMD3<Float>(xz * yz - xy * zz, det_y, xy * xz - yz * xx)
        } else {
            normal = SIMD3<Float>(xy * yz - xz * yy, xy * xz - yz * xx, det_z)
        }

        let len = simd_length(normal)
        guard len > 1e-10 else { return nil }

        normal /= len
        return (point: centroid, normal: normal)
    }

    /// Signed distance from a point to a plane.
    /// Positive = above plane (in direction of normal), negative = below.
    public static func signedDistanceToPlane(
        point: SIMD3<Float>,
        planePoint: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> Float {
        simd_dot(point - planePoint, planeNormal)
    }
}
