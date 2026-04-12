import Foundation
import simd

// MARK: - Perimeter Calculator

/// Computes the wound perimeter as the sum of Euclidean distances
/// between consecutive 3D boundary points projected onto the mesh.
public enum PerimeterCalculator {

    /// Compute perimeter from 3D boundary points.
    /// - Parameter points3D: Ordered 3D points along the wound boundary (closed polygon)
    /// - Returns: Perimeter in mm
    public static func computePerimeter(points3D: [SIMD3<Float>]) -> Double {
        guard points3D.count >= 3 else { return 0 }

        var perimeter: Float = 0
        let n = points3D.count

        for i in 0..<n {
            let j = (i + 1) % n
            perimeter += simd_distance(points3D[i], points3D[j])
        }

        // Meters to millimeters
        return Double(perimeter) * 1000.0
    }
}
