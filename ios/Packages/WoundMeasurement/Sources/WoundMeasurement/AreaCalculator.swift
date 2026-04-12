import Foundation
import simd

// MARK: - Area Calculator

/// Computes wound surface area from the clipped 3D mesh.
/// Sums the area of all triangles within the wound boundary.
/// ARKit works in meters; results are converted to cm².
public enum AreaCalculator {

    /// Compute the surface area of a clipped mesh in cm².
    /// - Parameter clippedMesh: Mesh clipped to wound boundary
    /// - Returns: Surface area in cm²
    public static func computeArea(clippedMesh: ClippedMesh) -> Double {
        // ClippedMesh already stores area in m²
        // Convert: 1 m² = 10,000 cm²
        Double(clippedMesh.surfaceAreaM2) * 10_000.0
    }

    /// Compute area directly from vertices and face indices.
    /// Used when you have raw geometry rather than a ClippedMesh.
    public static func computeArea(
        vertices: [SIMD3<Float>],
        faces: [(Int, Int, Int)]
    ) -> Double {
        var totalArea: Float = 0

        for (i0, i1, i2) in faces {
            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }
            totalArea += TriangleUtils.triangleArea(vertices[i0], vertices[i1], vertices[i2])
        }

        // Meters² to cm²
        return Double(totalArea) * 10_000.0
    }
}
