import Foundation
import simd
import WoundCore

// MARK: - Boundary Projector

/// Projects 2D image-space boundary points onto the 3D mesh surface.
/// Uses ray casting from the camera through each 2D point, with
/// the frozen ARKit mesh as the intersection target.
/// Falls back to depth-map lookup if ray-mesh intersection fails.
public final class BoundaryProjector {

    // MARK: - Public API

    /// Project normalized 2D boundary points onto the 3D mesh.
    /// - Parameters:
    ///   - points2D: Boundary points in normalized image coordinates (0...1)
    ///   - imageWidth: Width of the captured image in pixels
    ///   - imageHeight: Height of the captured image in pixels
    ///   - intrinsics: 3×3 camera intrinsics matrix
    ///   - cameraTransform: 4×4 camera-to-world transform
    ///   - vertices: Mesh vertices in world space
    ///   - faces: Mesh triangle indices
    ///   - depthMap: Fallback depth values (row-major, meters)
    ///   - depthWidth: Depth map width
    ///   - depthHeight: Depth map height
    /// - Returns: Array of 3D world-space points, same count as input
    public static func project(
        points2D: [SIMD2<Float>],
        imageWidth: Int,
        imageHeight: Int,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        depthMap: [Float],
        depthWidth: Int,
        depthHeight: Int
    ) throws -> [SIMD3<Float>] {

        guard !points2D.isEmpty else {
            throw MeasurementError.insufficientBoundaryPoints(count: 0, minimum: 3)
        }

        let cameraPosition = cameraTransform.translation
        let invIntrinsics = intrinsics.inverse

        var projected = [SIMD3<Float>]()
        projected.reserveCapacity(points2D.count)

        for point in points2D {
            // Convert normalized coords to pixel coords
            let px = point.x * Float(imageWidth)
            let py = point.y * Float(imageHeight)

            // Create ray from camera through the pixel
            let pixelHomogeneous = SIMD3<Float>(px, py, 1.0)
            let cameraSpaceDir = invIntrinsics * pixelHomogeneous
            let worldDir = cameraTransform.transformDirection(cameraSpaceDir).normalized

            // Try ray-mesh intersection first (most accurate)
            if let hit = rayMeshIntersection(
                origin: cameraPosition,
                direction: worldDir,
                vertices: vertices,
                faces: faces
            ) {
                projected.append(hit)
            } else {
                // Fallback: use depth map with bilinear interpolation
                let worldPoint = depthMapFallback(
                    normalizedPoint: point,
                    depthMap: depthMap,
                    depthWidth: depthWidth,
                    depthHeight: depthHeight,
                    intrinsics: intrinsics,
                    cameraTransform: cameraTransform
                )
                projected.append(worldPoint)
            }
        }

        return projected
    }

    // MARK: - Ray-Mesh Intersection

    /// Cast a ray and find the nearest triangle intersection.
    /// Uses Möller-Trumbore algorithm for each triangle.
    private static func rayMeshIntersection(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>]
    ) -> SIMD3<Float>? {

        var nearestT: Float = .greatestFiniteMagnitude
        var nearestPoint: SIMD3<Float>?
        let epsilon: Float = 1e-7

        for face in faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            // Möller-Trumbore intersection
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let h = direction.cross(edge2)
            let a = edge1.dot(h)

            // Ray is parallel to triangle
            guard abs(a) > epsilon else { continue }

            let f = 1.0 / a
            let s = origin - v0
            let u = f * s.dot(h)

            guard u >= 0.0, u <= 1.0 else { continue }

            let q = s.cross(edge1)
            let v = f * direction.dot(q)

            guard v >= 0.0, u + v <= 1.0 else { continue }

            let t = f * edge2.dot(q)

            // Intersection is in front of the ray and closer than previous
            if t > epsilon, t < nearestT {
                nearestT = t
                nearestPoint = origin + t * direction
            }
        }

        return nearestPoint
    }

    // MARK: - Depth Map Fallback

    /// Project a 2D point to 3D using the depth map with bilinear interpolation.
    private static func depthMapFallback(
        normalizedPoint: SIMD2<Float>,
        depthMap: [Float],
        depthWidth: Int,
        depthHeight: Int,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float> {

        // Map normalized image coords to depth map coords
        let dx = normalizedPoint.x * Float(depthWidth - 1)
        let dy = normalizedPoint.y * Float(depthHeight - 1)

        // Bilinear interpolation of depth
        let x0 = Int(dx)
        let y0 = Int(dy)
        let x1 = min(x0 + 1, depthWidth - 1)
        let y1 = min(y0 + 1, depthHeight - 1)

        let fx = dx - Float(x0)
        let fy = dy - Float(y0)

        let d00 = depthMap[y0 * depthWidth + x0]
        let d10 = depthMap[y0 * depthWidth + x1]
        let d01 = depthMap[y1 * depthWidth + x0]
        let d11 = depthMap[y1 * depthWidth + x1]

        let depth = d00 * (1 - fx) * (1 - fy)
            + d10 * fx * (1 - fy)
            + d01 * (1 - fx) * fy
            + d11 * fx * fy

        // Unproject to camera space using intrinsics
        let fx_cam = intrinsics[0][0]
        let fy_cam = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let pixelX = normalizedPoint.x * Float(depthWidth)
        let pixelY = normalizedPoint.y * Float(depthHeight)

        let cameraPoint = SIMD3<Float>(
            (pixelX - cx) * depth / fx_cam,
            (pixelY - cy) * depth / fy_cam,
            depth
        )

        // Transform to world space
        return cameraTransform.transformPoint(cameraPoint)
    }
}
