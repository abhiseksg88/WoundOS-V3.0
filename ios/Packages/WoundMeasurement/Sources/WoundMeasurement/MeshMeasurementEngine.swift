import Foundation
import simd
import WoundCore

// MARK: - Mesh Measurement Engine

/// Orchestrates the full on-device measurement pipeline:
/// 1. Clip mesh to wound boundary using MeshClipper.clip (rigorous Sutherland-Hodgman)
/// 2. Compute area from clipped triangles
/// 3. Fit reference plane to boundary → compute depth (with REAL camera position)
/// 4. Compute volume below reference plane
/// 5. Compute perimeter from 3D boundary points
/// 6. Compute length and width via rotating calipers (endpoints stored)
///
/// All computation uses the frozen ARKit data — no network calls.
public final class MeshMeasurementEngine {

    public init() {}

    // MARK: - Primary Entry Point

    /// Run the full measurement pipeline from frozen capture data + nurse boundary.
    /// This is the call site invoked by BoundaryDrawingViewModel.
    public func measure(
        captureData: CaptureData,
        boundary: WoundBoundary,
        qualityScore: CaptureQualityScore? = nil
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
            normals: normals,
            cameraIntrinsics: captureData.intrinsicsMatrix,
            cameraTransform: captureData.transformMatrix,
            imageWidth: captureData.imageWidth,
            imageHeight: captureData.imageHeight,
            qualityScore: qualityScore
        )
    }

    // MARK: - Core Measurement

    /// Compute all clinical measurements with full camera context.
    /// Uses MeshClipper.clip() (rigorous) instead of any approximate clipper.
    public func computeMeasurements(
        boundary: WoundBoundary,
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        normals: [SIMD3<Float>],
        cameraIntrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int,
        qualityScore: CaptureQualityScore? = nil
    ) throws -> WoundMeasurement {

        let startTime = CFAbsoluteTimeGetCurrent()

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

        // Step 1: Rigorous mesh clipping via Sutherland-Hodgman + camera projection
        let clippedMesh = MeshClipper.clip(
            vertices: vertices,
            faces: faces,
            boundary2D: boundary.points2D,
            intrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        guard !clippedMesh.isEmpty else {
            throw MeasurementError.noMeshIntersection
        }

        // Step 2: Area from clipped triangles
        let areaCm2 = AreaCalculator.computeArea(clippedMesh: clippedMesh)

        // Step 3: Depth — pass the REAL camera position so plane normal orients
        //          outward (toward camera).  This is the critical bug fix.
        let cameraPosition = cameraTransform.translation
        let depthResult = DepthCalculator.computeDepth(
            boundaryPoints3D: points3D,
            interiorVertices: clippedMesh.vertices,
            cameraPosition: cameraPosition
        )

        let maxDepthMm = depthResult?.maxDepthMm ?? 0
        let meanDepthMm = depthResult?.meanDepthMm ?? 0

        // Step 4: Volume relative to fitted plane
        var volumeMl: Double = 0
        if let depthResult {
            volumeMl = VolumeCalculator.computeVolume(
                clippedMesh: clippedMesh,
                referencePlanePoint: depthResult.referencePlanePoint,
                referencePlaneNormal: depthResult.referencePlaneNormal
            )
        }

        // Step 5: Perimeter from 3D boundary points
        let perimeterMm = PerimeterCalculator.computePerimeter(points3D: points3D)

        // Step 6: Length and width via rotating calipers — KEEP THE ENDPOINTS
        let dimensions: DimensionCalculator.DimensionResult
        if let depthResult {
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

        // Build the quality score with mesh hit rate + vertex count from this run
        let finalQuality = qualityScore.map { partial in
            CaptureQualityScore(
                trackingStableSeconds: partial.trackingStableSeconds,
                captureDistanceM: partial.captureDistanceM,
                meshVertexCount: clippedMesh.vertices.count,
                meanDepthConfidence: partial.meanDepthConfidence,
                meshHitRate: partial.meshHitRate,
                angularVelocityRadPerSec: partial.angularVelocityRadPerSec
            )
        }

        return WoundMeasurement(
            areaCm2: areaCm2,
            maxDepthMm: maxDepthMm,
            meanDepthMm: meanDepthMm,
            volumeMl: volumeMl,
            lengthMm: dimensions.lengthMm,
            widthMm: dimensions.widthMm,
            perimeterMm: perimeterMm,
            lengthEndpoints3D: [dimensions.lengthEndpoints.0, dimensions.lengthEndpoints.1],
            widthEndpoints3D: [dimensions.widthEndpoints.0, dimensions.widthEndpoints.1],
            qualityScore: finalQuality,
            source: .nurseBoundary,
            computedOnDevice: true,
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Helpers

    /// Estimate a normal from boundary points when no depth result is available.
    private func estimateNormal(from points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let plane = TriangleUtils.fitPlane(to: points) else {
            return SIMD3<Float>(0, 0, 1)
        }
        return plane.normal
    }
}
