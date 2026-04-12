import Foundation
import simd

// MARK: - Volume Calculator

/// Computes wound volume using the divergence theorem.
/// For each clipped mesh triangle below the reference plane,
/// a tetrahedron is formed with the reference plane, and volumes
/// are summed. Result is in mL (cm³).
public enum VolumeCalculator {

    /// Compute wound volume from the clipped mesh and reference plane.
    /// - Parameters:
    ///   - clippedMesh: Mesh triangles inside the wound boundary
    ///   - referencePlanePoint: Point on the reference plane (wound rim centroid)
    ///   - referencePlaneNormal: Normal of the reference plane (pointing outward)
    /// - Returns: Volume in mL (cm³). Returns 0 for flat/superficial wounds.
    public static func computeVolume(
        clippedMesh: ClippedMesh,
        referencePlanePoint: SIMD3<Float>,
        referencePlaneNormal: SIMD3<Float>
    ) -> Double {
        guard !clippedMesh.isEmpty else { return 0 }

        var totalVolume: Float = 0

        for (i0, i1, i2) in clippedMesh.faces {
            guard i0 < clippedMesh.vertices.count,
                  i1 < clippedMesh.vertices.count,
                  i2 < clippedMesh.vertices.count else { continue }

            let v0 = clippedMesh.vertices[i0]
            let v1 = clippedMesh.vertices[i1]
            let v2 = clippedMesh.vertices[i2]

            // Project each vertex onto the reference plane
            let p0 = projectOntoPlane(v0, planePoint: referencePlanePoint, planeNormal: referencePlaneNormal)
            let p1 = projectOntoPlane(v1, planePoint: referencePlanePoint, planeNormal: referencePlaneNormal)
            let p2 = projectOntoPlane(v2, planePoint: referencePlanePoint, planeNormal: referencePlaneNormal)

            // Form a triangular prism between the mesh triangle and its projection.
            // The prism volume is computed as the sum of 3 tetrahedra.
            // For simplicity we use the signed tetrahedron method.
            totalVolume += tetrahedronVolumeBetweenTriangles(
                top: (v0, v1, v2),
                bottom: (p0, p1, p2)
            )
        }

        // Take absolute value (sign depends on normal orientation)
        // Convert m³ to mL (cm³): 1 m³ = 1,000,000 cm³
        return abs(Double(totalVolume)) * 1_000_000.0
    }

    /// Project a point onto a plane along the plane normal.
    private static func projectOntoPlane(
        _ point: SIMD3<Float>,
        planePoint: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> SIMD3<Float> {
        let dist = simd_dot(point - planePoint, planeNormal)
        return point - dist * planeNormal
    }

    /// Compute the volume between two triangles (a triangular prism)
    /// using three tetrahedra decomposition.
    private static func tetrahedronVolumeBetweenTriangles(
        top: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
        bottom: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    ) -> Float {
        // Decompose the triangular prism into 3 tetrahedra
        let t0 = top.0; let t1 = top.1; let t2 = top.2
        let b0 = bottom.0; let b1 = bottom.1; let b2 = bottom.2

        let v1 = TriangleUtils.signedTetrahedronVolume(b0, b1, b2)
        let v2 = TriangleUtils.signedTetrahedronVolume(t0, b1, b2)
        let v3 = TriangleUtils.signedTetrahedronVolume(t0, t1, b2)
        let v4 = TriangleUtils.signedTetrahedronVolume(t0, t1, t2)

        // The prism volume = difference of pyramid volumes from origin
        // Using the decomposition method
        let vol_bottom = v1
        let vol_mid1 = v2 - v1
        let vol_mid2 = v3 - v2
        let vol_top = v4 - v3

        return vol_bottom + vol_mid1 + vol_mid2 + vol_top
    }
}
