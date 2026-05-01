import Foundation
import os
import simd
import WoundCore

private let logger = Logger(subsystem: "com.woundos.app", category: "Boundary")

// MARK: - Projection Result

/// Output of the boundary projector. Includes both the projected 3D
/// points and quality statistics (mesh hit rate + mean confidence)
/// that get folded into CaptureQualityScore.
public struct BoundaryProjectionResult {
    /// 3D world-space points, same count and order as input 2D points
    public let projectedPoints3D: [SIMD3<Float>]
    /// Fraction of points (0...1) that hit the mesh directly via ray-mesh
    /// intersection rather than depth-map fallback. 1.0 = all hits.
    public let meshHitRate: Double
    /// Mean LiDAR confidence (0...2) sampled at boundary points.
    /// Only counts samples that fell back to depth-map (mesh hits don't
    /// have a per-pixel confidence score).
    public let meanDepthConfidence: Double
}

// MARK: - Boundary Projector

/// Projects 2D image-space boundary points onto the 3D mesh surface.
/// Uses Möller-Trumbore ray-mesh intersection as the primary path
/// (highest accuracy, leverages ARKit's reconstructed mesh).
/// Falls back to depth-map sampling — but only on high-confidence pixels.
public final class BoundaryProjector {

    /// LiDAR confidence levels (per Apple): 0=low, 1=medium, 2=high.
    /// We only accept high.
    public static let minConfidence: UInt8 = 2

    /// Project boundary points and report quality statistics.
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
        depthHeight: Int,
        confidenceMap: [UInt8]
    ) throws -> BoundaryProjectionResult {

        guard !points2D.isEmpty else {
            logger.error("project() called with empty points2D")
            throw MeasurementError.insufficientBoundaryPoints(count: 0, minimum: 3)
        }

        let effectiveIntrinsics = validateAndCorrectIntrinsics(
            intrinsics,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        logger.info("project() — \(points2D.count) points, image=\(imageWidth)x\(imageHeight), mesh=\(vertices.count) verts/\(faces.count) faces, depth=\(depthWidth)x\(depthHeight)")
        let cameraPosition = cameraTransform.translation
        let invIntrinsics = effectiveIntrinsics.inverse

        var projected = [SIMD3<Float>]()
        projected.reserveCapacity(points2D.count)

        var meshHits = 0
        var confidenceSum = 0.0
        var confidenceSamples = 0

        for point in points2D {
            // Convert normalized → pixel
            let px = point.x * Float(imageWidth)
            let py = point.y * Float(imageHeight)

            // Ray from camera through pixel
            let pixelHomogeneous = SIMD3<Float>(px, py, 1.0)
            let cameraSpaceDir = invIntrinsics * pixelHomogeneous
            let worldDir = cameraTransform.transformDirection(cameraSpaceDir).normalized

            // Primary: Möller-Trumbore against the frozen mesh
            if let hit = rayMeshIntersection(
                origin: cameraPosition,
                direction: worldDir,
                vertices: vertices,
                faces: faces
            ) {
                projected.append(hit)
                meshHits += 1
            } else {
                // Fallback: depth-map sampling on HIGH-CONFIDENCE pixels only
                let (worldPoint, sampledConfidence) = depthMapFallback(
                    normalizedPoint: point,
                    depthMap: depthMap,
                    depthWidth: depthWidth,
                    depthHeight: depthHeight,
                    confidenceMap: confidenceMap,
                    intrinsics: effectiveIntrinsics,
                    cameraTransform: cameraTransform,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight
                )
                projected.append(worldPoint)
                confidenceSum += sampledConfidence
                confidenceSamples += 1
            }
        }

        let hitRate = Double(meshHits) / Double(points2D.count)
        let meanConf = confidenceSamples > 0
            ? confidenceSum / Double(confidenceSamples)
            : 2.0   // all mesh hits → treat as full confidence

        logger.info("Projection done — meshHits=\(meshHits)/\(points2D.count) hitRate=\(String(format: "%.2f", hitRate)) meanConf=\(String(format: "%.2f", meanConf)) depthFallbacks=\(confidenceSamples)")

        return BoundaryProjectionResult(
            projectedPoints3D: projected,
            meshHitRate: hitRate,
            meanDepthConfidence: meanConf
        )
    }

    // MARK: - Ray-Mesh Intersection (Möller-Trumbore)

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

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let h = direction.cross(edge2)
            let a = edge1.dot(h)
            guard abs(a) > epsilon else { continue }

            let f = 1.0 / a
            let s = origin - v0
            let u = f * s.dot(h)
            guard u >= 0.0, u <= 1.0 else { continue }

            let q = s.cross(edge1)
            let v = f * direction.dot(q)
            guard v >= 0.0, u + v <= 1.0 else { continue }

            let t = f * edge2.dot(q)
            if t > epsilon, t < nearestT {
                nearestT = t
                nearestPoint = origin + t * direction
            }
        }

        return nearestPoint
    }

    // MARK: - Intrinsics Validation

    /// Detect and correct intrinsics/resolution mismatches.
    /// ARKit's frame.camera.intrinsics should be calibrated for the actual
    /// capturedImage resolution, but on some device/format combinations the
    /// principal point (cx, cy) falls outside the expected range, indicating
    /// the intrinsics are calibrated for a different resolution.
    private static func validateAndCorrectIntrinsics(
        _ intrinsics: simd_float3x3,
        imageWidth: Int,
        imageHeight: Int
    ) -> simd_float3x3 {
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let halfW = Float(imageWidth) / 2.0
        let halfH = Float(imageHeight) / 2.0

        logger.info("INTRINSICS CHECK: fx=\(fx) fy=\(fy) cx=\(cx) cy=\(cy) | image=\(imageWidth)x\(imageHeight) halfW=\(halfW) halfH=\(halfH)")

        let ratioX = cx / halfW
        let ratioY = cy / halfH
        logger.info("INTRINSICS CHECK: cx/halfW=\(String(format: "%.3f", ratioX)) cy/halfH=\(String(format: "%.3f", ratioY))")

        // cx should be approximately imageWidth/2 (within 80%).
        // If significantly off, the intrinsics are for a different resolution.
        if ratioX > 1.8 || ratioX < 0.55 || ratioY > 1.8 || ratioY < 0.55 {
            let scale = halfW / cx
            logger.warning("INTRINSICS MISMATCH: cx=\(cx) vs expected≈\(halfW), cy=\(cy) vs expected≈\(halfH). Correcting by scale=\(scale)")

            return simd_float3x3(
                SIMD3<Float>(fx * scale, 0, 0),
                SIMD3<Float>(0, fy * scale, 0),
                SIMD3<Float>(cx * scale, cy * scale, 1)
            )
        }

        return intrinsics
    }

    // MARK: - Depth Map Fallback (Confidence-Filtered)

    /// Sample the depth map at the point's coordinates, but only consider
    /// pixels with confidence ≥ minConfidence. If all 4 nearest neighbors
    /// are low-confidence, expand outward to find the nearest high-confidence
    /// sample within a small search radius.
    /// Returns (worldPoint, mean sampled confidence value).
    private static func depthMapFallback(
        normalizedPoint: SIMD2<Float>,
        depthMap: [Float],
        depthWidth: Int,
        depthHeight: Int,
        confidenceMap: [UInt8],
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) -> (SIMD3<Float>, Double) {

        let dx = normalizedPoint.x * Float(depthWidth - 1)
        let dy = normalizedPoint.y * Float(depthHeight - 1)

        let centerX = Int(dx.rounded())
        let centerY = Int(dy.rounded())

        // Look for nearest high-confidence pixel within a small window
        var bestDepth: Float = 0
        var bestConf: UInt8 = 0
        var foundHighConf = false

        let searchRadius = 4
        var minDist = Int.max

        for dyOff in -searchRadius...searchRadius {
            for dxOff in -searchRadius...searchRadius {
                let row = centerY + dyOff
                let col = centerX + dxOff
                guard row >= 0, row < depthHeight, col >= 0, col < depthWidth else { continue }

                let idx = row * depthWidth + col
                guard idx < depthMap.count else { continue }

                let conf: UInt8 = idx < confidenceMap.count ? confidenceMap[idx] : 0
                let depth = depthMap[idx]
                guard depth > 0, depth.isFinite else { continue }

                if conf >= minConfidence {
                    let dist = dxOff * dxOff + dyOff * dyOff
                    if dist < minDist {
                        minDist = dist
                        bestDepth = depth
                        bestConf = conf
                        foundHighConf = true
                    }
                }
            }
        }

        // If no high-confidence sample found, use bilinear interpolation
        // as a last resort and report the (low) confidence.
        if !foundHighConf {
            let x0 = max(0, min(centerX, depthWidth - 1))
            let y0 = max(0, min(centerY, depthHeight - 1))
            let idx = y0 * depthWidth + x0
            bestDepth = idx < depthMap.count ? depthMap[idx] : 0
            bestConf = idx < confidenceMap.count ? confidenceMap[idx] : 0
        }

        // Unproject to camera space.
        // Camera intrinsics reference the full RGB image resolution,
        // NOT the (smaller) depth map resolution. Use imageWidth/Height
        // for the pixel coordinates that feed into the intrinsics.
        let fx_cam = intrinsics[0][0]
        let fy_cam = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let pixelX = normalizedPoint.x * Float(imageWidth)
        let pixelY = normalizedPoint.y * Float(imageHeight)

        let cameraPoint = SIMD3<Float>(
            (pixelX - cx) * bestDepth / fx_cam,
            (pixelY - cy) * bestDepth / fy_cam,
            bestDepth
        )

        let worldPoint = cameraTransform.transformPoint(cameraPoint)
        return (worldPoint, Double(bestConf))
    }
}
