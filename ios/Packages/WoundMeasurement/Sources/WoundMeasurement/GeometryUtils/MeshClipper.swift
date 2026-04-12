import Foundation
import simd
import WoundCore

// MARK: - Clipped Mesh

/// Result of clipping a 3D mesh to a wound boundary.
/// Contains only the triangles (or partial triangles) that fall
/// inside the projected boundary.
public struct ClippedMesh {
    /// Vertices of the clipped mesh (world space)
    public let vertices: [SIMD3<Float>]
    /// Triangle face indices into `vertices`
    public let faces: [(Int, Int, Int)]
    /// Total surface area in square meters
    public let surfaceAreaM2: Float

    public var isEmpty: Bool { faces.isEmpty }
}

// MARK: - Mesh Clipper

/// Clips a 3D mesh to only the triangles inside a wound boundary.
/// The boundary is defined in 2D (normalized image coords) and the
/// mesh vertices are projected to 2D for the containment test.
/// Boundary-crossing triangles are subdivided using Sutherland-Hodgman.
public enum MeshClipper {

    /// Clip the mesh to the wound boundary.
    /// - Parameters:
    ///   - vertices: All mesh vertices in world space
    ///   - faces: Triangle face indices
    ///   - boundary2D: Wound boundary in normalized image coords (closed polygon)
    ///   - intrinsics: Camera intrinsics for projecting 3D → 2D
    ///   - cameraTransform: Camera-to-world transform
    ///   - imageWidth: Image width for projection
    ///   - imageHeight: Image height for projection
    /// - Returns: ClippedMesh containing only wound-interior geometry
    public static func clip(
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        boundary2D: [SIMD2<Float>],
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) -> ClippedMesh {
        guard boundary2D.count >= 3 else {
            return ClippedMesh(vertices: [], faces: [], surfaceAreaM2: 0)
        }

        // Project all mesh vertices to 2D normalized image coordinates
        let projectedVertices = projectVerticesToImage(
            vertices: vertices,
            intrinsics: intrinsics,
            cameraTransform: cameraTransform,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        var clippedVertices = [SIMD3<Float>]()
        var clippedFaces = [(Int, Int, Int)]()
        var totalArea: Float = 0

        for face in faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let p0 = projectedVertices[i0]
            let p1 = projectedVertices[i1]
            let p2 = projectedVertices[i2]

            let in0 = isPointInPolygon(p0, polygon: boundary2D)
            let in1 = isPointInPolygon(p1, polygon: boundary2D)
            let in2 = isPointInPolygon(p2, polygon: boundary2D)

            if in0 && in1 && in2 {
                // Fully inside — keep the entire triangle
                let baseIdx = clippedVertices.count
                clippedVertices.append(vertices[i0])
                clippedVertices.append(vertices[i1])
                clippedVertices.append(vertices[i2])
                clippedFaces.append((baseIdx, baseIdx + 1, baseIdx + 2))
                totalArea += TriangleUtils.triangleArea(vertices[i0], vertices[i1], vertices[i2])
            } else if in0 || in1 || in2 {
                // Partially inside — clip the triangle against the boundary
                let triangleVerts2D = [p0, p1, p2]
                let triangleVerts3D = [vertices[i0], vertices[i1], vertices[i2]]

                let clippedPolygon = sutherlandHodgmanClip(
                    subject: triangleVerts2D,
                    clip: boundary2D
                )

                guard clippedPolygon.count >= 3 else { continue }

                // Interpolate 3D positions for clipped polygon vertices
                let clipped3D = clippedPolygon.map { pt2d -> SIMD3<Float> in
                    interpolate3DFromBarycentric(
                        point2D: pt2d,
                        triangle2D: triangleVerts2D,
                        triangle3D: triangleVerts3D
                    )
                }

                // Fan-triangulate the clipped polygon
                let baseIdx = clippedVertices.count
                clippedVertices.append(contentsOf: clipped3D)
                for j in 1..<(clipped3D.count - 1) {
                    clippedFaces.append((baseIdx, baseIdx + j, baseIdx + j + 1))
                    totalArea += TriangleUtils.triangleArea(
                        clipped3D[0], clipped3D[j], clipped3D[j + 1]
                    )
                }
            }
            // Fully outside — skip
        }

        return ClippedMesh(
            vertices: clippedVertices,
            faces: clippedFaces,
            surfaceAreaM2: totalArea
        )
    }

    // MARK: - 3D → 2D Projection

    /// Project 3D world-space vertices to normalized image coordinates.
    static func projectVerticesToImage(
        vertices: [SIMD3<Float>],
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) -> [SIMD2<Float>] {
        let viewMatrix = cameraTransform.inverse

        return vertices.map { worldPoint in
            // Transform to camera space
            let camPoint4 = viewMatrix * SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)
            let camPoint = SIMD3<Float>(camPoint4.x, camPoint4.y, camPoint4.z)

            // Project with intrinsics
            let projected = intrinsics * camPoint
            guard abs(projected.z) > 1e-6 else { return SIMD2<Float>(-1, -1) }

            // Normalize to 0...1
            return SIMD2<Float>(
                projected.x / (projected.z * Float(imageWidth)),
                projected.y / (projected.z * Float(imageHeight))
            )
        }
    }

    // MARK: - Point-in-Polygon (Winding Number)

    /// Winding number test for point-in-polygon.
    /// More robust than ray-casting for edge cases.
    public static func isPointInPolygon(_ point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        let n = polygon.count
        guard n >= 3 else { return false }

        var windingNumber = 0

        for i in 0..<n {
            let j = (i + 1) % n
            let vi = polygon[i]
            let vj = polygon[j]

            if vi.y <= point.y {
                if vj.y > point.y {
                    // Upward crossing
                    if isLeft(vi, vj, point) > 0 {
                        windingNumber += 1
                    }
                }
            } else {
                if vj.y <= point.y {
                    // Downward crossing
                    if isLeft(vi, vj, point) < 0 {
                        windingNumber -= 1
                    }
                }
            }
        }

        return windingNumber != 0
    }

    private static func isLeft(
        _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ p: SIMD2<Float>
    ) -> Float {
        (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
    }

    // MARK: - Sutherland-Hodgman Clipping

    /// Clip a convex/concave polygon against a clip polygon.
    static func sutherlandHodgmanClip(
        subject: [SIMD2<Float>],
        clip: [SIMD2<Float>]
    ) -> [SIMD2<Float>] {
        var output = subject

        for i in 0..<clip.count {
            guard !output.isEmpty else { return [] }

            let edgeStart = clip[i]
            let edgeEnd = clip[(i + 1) % clip.count]
            var input = output
            output = []

            for j in 0..<input.count {
                let current = input[j]
                let previous = input[(j + input.count - 1) % input.count]

                let currInside = isLeft(edgeStart, edgeEnd, current) >= 0
                let prevInside = isLeft(edgeStart, edgeEnd, previous) >= 0

                if currInside {
                    if !prevInside {
                        if let intersection = lineIntersection(previous, current, edgeStart, edgeEnd) {
                            output.append(intersection)
                        }
                    }
                    output.append(current)
                } else if prevInside {
                    if let intersection = lineIntersection(previous, current, edgeStart, edgeEnd) {
                        output.append(intersection)
                    }
                }
            }
        }

        return output
    }

    private static func lineIntersection(
        _ a1: SIMD2<Float>, _ a2: SIMD2<Float>,
        _ b1: SIMD2<Float>, _ b2: SIMD2<Float>
    ) -> SIMD2<Float>? {
        let d1 = a2 - a1
        let d2 = b2 - b1
        let cross = d1.x * d2.y - d1.y * d2.x

        guard abs(cross) > 1e-10 else { return nil }

        let d3 = b1 - a1
        let t = (d3.x * d2.y - d3.y * d2.x) / cross

        return a1 + t * d1
    }

    // MARK: - Barycentric Interpolation

    /// Given a 2D point inside a 2D triangle, compute its barycentric coordinates
    /// and use them to interpolate a 3D position from the 3D triangle.
    static func interpolate3DFromBarycentric(
        point2D: SIMD2<Float>,
        triangle2D: [SIMD2<Float>],
        triangle3D: [SIMD3<Float>]
    ) -> SIMD3<Float> {
        let (u, v, w) = barycentricCoordinates(
            point: point2D,
            a: triangle2D[0],
            b: triangle2D[1],
            c: triangle2D[2]
        )
        return u * triangle3D[0] + v * triangle3D[1] + w * triangle3D[2]
    }

    static func barycentricCoordinates(
        point p: SIMD2<Float>,
        a: SIMD2<Float>,
        b: SIMD2<Float>,
        c: SIMD2<Float>
    ) -> (Float, Float, Float) {
        let v0 = b - a
        let v1 = c - a
        let v2 = p - a

        let d00 = simd_dot(v0, v0)
        let d01 = simd_dot(v0, v1)
        let d11 = simd_dot(v1, v1)
        let d20 = simd_dot(v2, v0)
        let d21 = simd_dot(v2, v1)

        let denom = d00 * d11 - d01 * d01
        guard abs(denom) > 1e-10 else { return (1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0) }

        let v = (d11 * d20 - d01 * d21) / denom
        let w = (d00 * d21 - d01 * d20) / denom
        let u = 1.0 - v - w

        return (u, v, w)
    }
}
