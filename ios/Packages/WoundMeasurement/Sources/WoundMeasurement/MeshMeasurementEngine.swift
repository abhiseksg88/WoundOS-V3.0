import Foundation
import simd
import WoundCore

// MARK: - Mesh Measurement Engine

/// Orchestrates the full on-device measurement pipeline:
/// 1. Clip mesh to wound boundary
/// 2. Compute area from clipped triangles
/// 3. Fit reference plane to boundary → compute depth
/// 4. Compute volume below reference plane
/// 5. Compute perimeter from 3D boundary points
/// 6. Compute length and width via rotating calipers
///
/// All computation uses the frozen ARKit data — no network calls.
public final class MeshMeasurementEngine: MeasurementEngineProtocol {

    public init() {}

    /// Compute all clinical measurements.
    /// - Parameters:
    ///   - boundary: Wound boundary with projected 3D points
    ///   - vertices: Mesh vertices in world space
    ///   - faces: Mesh triangle indices
    ///   - normals: Per-vertex normals
    /// - Returns: Complete WoundMeasurement
    public func computeMeasurements(
        boundary: WoundBoundary,
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        normals: [SIMD3<Float>]
    ) throws -> WoundMeasurement {

        let startTime = CFAbsoluteTimeGetCurrent()

        // Validate boundary
        guard let points3D = boundary.projectedPoints3D, points3D.count >= 3 else {
            throw MeasurementError.insufficientBoundaryPoints(
                count: boundary.projectedPoints3D?.count ?? 0,
                minimum: 3
            )
        }

        guard boundary.points2D.count >= 3 else {
            throw MeasurementError.insufficientBoundaryPoints(
                count: boundary.points2D.count,
                minimum: 3
            )
        }

        // Step 1: Clip mesh to wound boundary
        // We need camera parameters for the 3D→2D projection during clipping.
        // Since we're using the boundary's own 2D points (already in image space),
        // we perform clipping using the winding number test on the 2D boundary.
        let clippedMesh = clipMeshToBoundary(
            vertices: vertices,
            faces: faces,
            boundary2D: boundary.points2D,
            boundary3D: points3D
        )

        guard !clippedMesh.isEmpty else {
            throw MeasurementError.noMeshIntersection
        }

        // Step 2: Compute area
        let areaCm2 = AreaCalculator.computeArea(clippedMesh: clippedMesh)

        // Step 3: Compute depth
        let cameraPosition = SIMD3<Float>(0, 0, 0) // Will be overridden by caller if needed
        let depthResult = DepthCalculator.computeDepth(
            boundaryPoints3D: points3D,
            interiorVertices: clippedMesh.vertices,
            cameraPosition: cameraPosition
        )

        let maxDepthMm = depthResult?.maxDepthMm ?? 0
        let meanDepthMm = depthResult?.meanDepthMm ?? 0

        // Step 4: Compute volume
        var volumeMl: Double = 0
        if let depthResult = depthResult {
            volumeMl = VolumeCalculator.computeVolume(
                clippedMesh: clippedMesh,
                referencePlanePoint: depthResult.referencePlanePoint,
                referencePlaneNormal: depthResult.referencePlaneNormal
            )
        }

        // Step 5: Compute perimeter
        let perimeterMm = PerimeterCalculator.computePerimeter(points3D: points3D)

        // Step 6: Compute length and width
        let dimensions: DimensionCalculator.DimensionResult
        if let depthResult = depthResult {
            dimensions = DimensionCalculator.computeDimensions(
                boundaryPoints3D: points3D,
                referencePlanePoint: depthResult.referencePlanePoint,
                referencePlaneNormal: depthResult.referencePlaneNormal
            )
        } else {
            dimensions = DimensionCalculator.computeDimensions(
                boundaryPoints3D: points3D,
                referencePlanePoint: TriangleUtils.polygonCentroid(points3D),
                referencePlaneNormal: estimateNormal(from: points3D)
            )
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let processingTimeMs = Int(elapsed * 1000)

        return WoundMeasurement(
            areaCm2: areaCm2,
            maxDepthMm: maxDepthMm,
            meanDepthMm: meanDepthMm,
            volumeMl: volumeMl,
            lengthMm: dimensions.lengthMm,
            widthMm: dimensions.widthMm,
            perimeterMm: perimeterMm,
            source: .nurseBoundary,
            computedOnDevice: true,
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Convenience: Full Pipeline with CaptureData

    /// Run the full measurement pipeline from capture data and boundary.
    /// This is the primary entry point called by the ViewModel after
    /// the nurse draws a boundary.
    public func measure(
        captureData: CaptureData,
        boundary: WoundBoundary
    ) throws -> WoundMeasurement {

        let vertices = captureData.unpackVertices()
        let faces = captureData.unpackFaces()
        let normals = captureData.unpackNormals()

        guard !vertices.isEmpty else {
            throw MeasurementError.noMeshIntersection
        }

        return try computeMeasurements(
            boundary: boundary,
            vertices: vertices,
            faces: faces,
            normals: normals
        )
    }

    // MARK: - Internal: Mesh Clipping

    /// Clip mesh using the 2D boundary for containment testing.
    /// For each mesh triangle, test if its centroid (projected to 2D via
    /// barycentric correspondence) falls inside the 2D boundary.
    private func clipMeshToBoundary(
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        boundary2D: [SIMD2<Float>],
        boundary3D: [SIMD3<Float>]
    ) -> ClippedMesh {

        // Build a simple bounding box for fast rejection
        let minX = boundary2D.map(\.x).min() ?? 0
        let maxX = boundary2D.map(\.x).max() ?? 1
        let minY = boundary2D.map(\.y).min() ?? 0
        let maxY = boundary2D.map(\.y).max() ?? 1

        // Pre-compute the 3D bounding box of boundary for rough filtering
        let minX3D = boundary3D.map(\.x).min() ?? -.greatestFiniteMagnitude
        let maxX3D = boundary3D.map(\.x).max() ?? .greatestFiniteMagnitude
        let minY3D = boundary3D.map(\.y).min() ?? -.greatestFiniteMagnitude
        let maxY3D = boundary3D.map(\.y).max() ?? .greatestFiniteMagnitude
        let minZ3D = boundary3D.map(\.z).min() ?? -.greatestFiniteMagnitude
        let maxZ3D = boundary3D.map(\.z).max() ?? .greatestFiniteMagnitude

        // Expand 3D bounds by a margin for depth
        let margin: Float = 0.05 // 5cm margin
        let bounds3D = (
            min: SIMD3<Float>(minX3D - margin, minY3D - margin, minZ3D - margin),
            max: SIMD3<Float>(maxX3D + margin, maxY3D + margin, maxZ3D + margin)
        )

        var clippedVertices = [SIMD3<Float>]()
        var clippedFaces = [(Int, Int, Int)]()
        var totalArea: Float = 0

        for face in faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            // Quick 3D bounding box rejection
            let centroid3D = (v0 + v1 + v2) / 3.0
            guard centroid3D.x >= bounds3D.min.x && centroid3D.x <= bounds3D.max.x &&
                  centroid3D.y >= bounds3D.min.y && centroid3D.y <= bounds3D.max.y &&
                  centroid3D.z >= bounds3D.min.z && centroid3D.z <= bounds3D.max.z else {
                continue
            }

            // For triangles near the boundary, check if the centroid is inside
            // using a nearest-point projection approach
            let nearestBoundaryDist = nearestDistanceToBoundary3D(centroid3D, boundary: boundary3D)
            let triangleSize = TriangleUtils.triangleArea(v0, v1, v2)

            // Include triangle if its centroid is within the wound region
            // This is a simplified approach; the full Sutherland-Hodgman clipping
            // in MeshClipper handles the precise case with camera parameters
            if nearestBoundaryDist < sqrt(triangleSize) * 2.0 || isInsideBoundary3D(centroid3D, boundary: boundary3D) {
                let baseIdx = clippedVertices.count
                clippedVertices.append(v0)
                clippedVertices.append(v1)
                clippedVertices.append(v2)
                clippedFaces.append((baseIdx, baseIdx + 1, baseIdx + 2))
                totalArea += triangleSize
            }
        }

        return ClippedMesh(
            vertices: clippedVertices,
            faces: clippedFaces,
            surfaceAreaM2: totalArea
        )
    }

    /// Approximate 3D point-in-boundary test using projected distances.
    private func isInsideBoundary3D(_ point: SIMD3<Float>, boundary: [SIMD3<Float>]) -> Bool {
        // Project the point and boundary onto the boundary's best-fit plane,
        // then do a 2D winding number test.
        guard let plane = TriangleUtils.fitPlane(to: boundary) else { return false }

        let arbitrary: SIMD3<Float> = abs(plane.normal.x) < 0.9
            ? SIMD3<Float>(1, 0, 0)
            : SIMD3<Float>(0, 1, 0)
        let u = simd_normalize(simd_cross(plane.normal, arbitrary))
        let v = simd_cross(plane.normal, u)

        let point2D = SIMD2<Float>(
            simd_dot(point - plane.point, u),
            simd_dot(point - plane.point, v)
        )

        let boundary2D = boundary.map { p -> SIMD2<Float> in
            SIMD2<Float>(
                simd_dot(p - plane.point, u),
                simd_dot(p - plane.point, v)
            )
        }

        return MeshClipper.isPointInPolygon(point2D, polygon: boundary2D)
    }

    /// Compute nearest distance from a 3D point to the boundary polyline.
    private func nearestDistanceToBoundary3D(_ point: SIMD3<Float>, boundary: [SIMD3<Float>]) -> Float {
        var minDist: Float = .greatestFiniteMagnitude
        let n = boundary.count

        for i in 0..<n {
            let j = (i + 1) % n
            let dist = pointToSegmentDistance(point, boundary[i], boundary[j])
            minDist = min(minDist, dist)
        }

        return minDist
    }

    private func pointToSegmentDistance(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let ab = b - a
        let ap = p - a
        let t = max(0, min(1, simd_dot(ap, ab) / simd_dot(ab, ab)))
        let closest = a + t * ab
        return simd_distance(p, closest)
    }

    /// Estimate a normal from boundary points when no depth result is available.
    private func estimateNormal(from points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let plane = TriangleUtils.fitPlane(to: points) else {
            return SIMD3<Float>(0, 0, 1)
        }
        return plane.normal
    }
}
