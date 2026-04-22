import Foundation
import Combine
import simd
import UIKit
import WoundCore
import WoundBoundary
import WoundMeasurement
import WoundAutoSegmentation

// MARK: - Boundary Drawing View Model

final class BoundaryDrawingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var drawingMode: DrawingMode = .tapPoint
    @Published var tapPoint: CGPoint?
    @Published var boundaryFinalized = false
    @Published var isComputing = false
    @Published var isAutoSegmenting = false
    @Published var error: String?
    @Published var validationErrors: [BoundaryValidationError] = []

    /// Emits the polygon produced by auto-segmentation so the VC can load it
    /// into the canvas for the nurse to edit.
    let autoSegmentationResult = PassthroughSubject<[CGPoint], Never>()

    // MARK: - Navigation

    var onMeasurementComplete: ((WoundScan) -> Void)?

    // MARK: - Data

    let snapshot: CaptureSnapshot
    private let measurementEngine: MeshMeasurementEngine
    private let segmenter: WoundSegmenter?
    /// Pre-stamped quality score from the live capture moment.
    /// Includes mesh hit rate / confidence after measurement runs.
    private let qualityScoreSnapshot: CaptureQualityScore?
    private var normalizedTapPoint: SIMD2<Float>?
    private var normalizedBoundaryPoints: [SIMD2<Float>] = []
    /// Tracks whether the current boundary was seeded by the auto-segmenter
    /// (even if the nurse then edited it). Stored with the scan so audit
    /// trails can distinguish AI-assisted from purely manual boundaries.
    private var boundaryWasAutoSeeded = false
    private(set) var segmenterModelId: String?

    /// Exposes the model identifier of the last successful segmentation
    /// so the VC can indicate which model detected the boundary.
    var lastSegmenterModelId: String? { segmenterModelId }

    /// The captured RGB image for display, cached to avoid repeated JPEG decoding.
    /// ARKit's pixel buffer is always landscape-right. Apply `.right`
    /// orientation so UIImageView displays it in portrait.
    lazy var capturedImage: UIImage? = {
        guard let raw = UIImage(data: snapshot.rgbImageData),
              let cg = raw.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .right)
    }()

    /// Raw landscape CGImage for passing to the segmenter (no orientation
    /// rotation — Vision needs the raw sensor pixels).
    private var rawCGImage: CGImage? {
        UIImage(data: snapshot.rgbImageData)?.cgImage
    }

    var instructionText: String {
        switch drawingMode {
        case .tapPoint:
            return "Tap the center of the wound"
        case .polygon:
            return "Tap around the wound edge to place points"
        case .freeform:
            return "Trace your finger around the wound edge"
        case .auto:
            return autoSegmenterAvailable
                ? "Tap the center of the wound"
                : "Auto-detect unavailable. Switch to Draw Manually."
        }
    }

    /// True when a segmenter is injected and the current OS supports it.
    /// The VC uses this to enable/disable the "Auto" segment.
    var autoSegmenterAvailable: Bool { segmenter != nil }

    // MARK: - Init

    init(
        snapshot: CaptureSnapshot,
        measurementEngine: MeshMeasurementEngine,
        segmenter: WoundSegmenter? = nil,
        qualityScoreSnapshot: CaptureQualityScore? = nil
    ) {
        self.snapshot = snapshot
        self.measurementEngine = measurementEngine
        self.segmenter = segmenter
        self.qualityScoreSnapshot = qualityScoreSnapshot

        // Default to Auto when a segmenter is available so the nurse flow is:
        // tap center → polygon appears → edit if needed → Measure.
        if segmenter != nil {
            self.drawingMode = .auto
        }
    }

    // MARK: - Tap Point

    func didPlaceTapPoint(_ point: CGPoint, in geometry: ImageViewGeometry) {
        tapPoint = point
        normalizedTapPoint = geometry.viewToSensorNormalized(point)

        // In .auto mode, the tap is a point prompt for the segmenter. The VC
        // subscribes to `autoSegmentationResult` and seeds the canvas with
        // the resulting polygon. Otherwise, advance to polygon drawing mode.
        if drawingMode == .auto {
            runAutoSegmentation(tapPoint: point, geometry: geometry)
        } else {
            drawingMode = .polygon
        }
    }

    // MARK: - Auto Segmentation

    func runAutoSegmentation(tapPoint: CGPoint, geometry: ImageViewGeometry) {
        CrashLogger.shared.log("Auto-segmentation requested at tap=\(tapPoint)", category: .segmentation)
        guard let segmenter else {
            CrashLogger.shared.error("No segmenter available", category: .segmentation)
            error = "Auto-detect is not available on this device."
            return
        }
        // Use the raw landscape CGImage — Vision needs sensor-oriented pixels.
        guard let cgImage = rawCGImage else {
            CrashLogger.shared.error("rawCGImage is nil — cannot segment", category: .segmentation)
            error = "Captured image is unavailable."
            return
        }

        // Convert tap from view-local coords to sensor pixel coords,
        // accounting for portrait display → landscape sensor rotation.
        guard geometry.fittedRect.contains(tapPoint) else {
            CrashLogger.shared.log("Tap outside image area: \(tapPoint) not in \(geometry.fittedRect)", category: .segmentation, level: .warning)
            error = "Tap inside the image area."
            return
        }
        let sensorTap = geometry.viewToSensorPixel(tapPoint)
        CrashLogger.shared.log("Sensor tap coords: \(sensorTap), image: \(cgImage.width)x\(cgImage.height)", category: .segmentation)

        isAutoSegmenting = true
        Task { @MainActor in
            defer { isAutoSegmenting = false }
            do {
                let result = try await segmenter.segment(
                    image: cgImage,
                    tapPoint: sensorTap
                )
                CrashLogger.shared.log("Segmentation success: \(result.polygonImageSpace.count) polygon points, model=\(result.modelIdentifier)", category: .segmentation)

                // Sanity check: reject polygons that cover an unreasonable
                // fraction of the image. The threshold depends on the model:
                // SAM 2 (server) is wound-specific and reliable at high coverage;
                // on-device fallbacks (Vision/CoreML) are more prone to grabbing
                // the entire foreground.
                let polyArea = Self.polygonArea(result.polygonImageSpace)
                let imageArea = result.imageSize.width * result.imageSize.height
                let coverage = polyArea / imageArea
                let isSAM2 = result.modelIdentifier.hasPrefix("sam2")
                let maxCoverage: CGFloat = isSAM2 ? 0.80 : 0.50
                CrashLogger.shared.log("Polygon coverage: \(String(format: "%.1f%%", coverage * 100)) of image, model=\(result.modelIdentifier), maxAllowed=\(String(format: "%.0f%%", maxCoverage * 100))", category: .segmentation)

                if coverage > maxCoverage {
                    CrashLogger.shared.log("Polygon rejected — covers \(String(format: "%.0f%%", coverage * 100)) of image (max \(String(format: "%.0f%%", maxCoverage * 100)))", category: .segmentation, level: .warning)
                    self.error = "Detection too large — tap directly on the wound, or use Draw Manually."
                    return
                }

                // Project polygon from sensor pixels back to view-local coords.
                let viewPolygon = result.polygonImageSpace.map { sensorPt in
                    geometry.sensorPixelToViewPoint(sensorPt)
                }
                boundaryWasAutoSeeded = true
                segmenterModelId = result.modelIdentifier
                autoSegmentationResult.send(viewPolygon)
            } catch {
                CrashLogger.shared.error("Auto-segmentation failed", category: .segmentation, error: error)
                self.error = "Segmentation failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Boundary Updates

    func didUpdateBoundary(_ points: [CGPoint], in geometry: ImageViewGeometry) {
        normalizedBoundaryPoints = points.map { geometry.viewToSensorNormalized($0) }
        // Enable Measure as soon as polygon has 3+ points — the measurement
        // pipeline auto-closes the polygon. This avoids requiring the user
        // to tap near the first vertex to "close" the polygon.
        if drawingMode == .polygon && normalizedBoundaryPoints.count >= 3 {
            boundaryFinalized = true
        }
    }

    func didFinalizeBoundary(_ points: [CGPoint], in geometry: ImageViewGeometry) {
        CrashLogger.shared.log("didFinalizeBoundary: \(points.count) view-space points, geometry.fittedRect=\(geometry.fittedRect)", category: .boundary)
        normalizedBoundaryPoints = points.map { geometry.viewToSensorNormalized($0) }
        CrashLogger.shared.log("didFinalizeBoundary: normalized \(normalizedBoundaryPoints.count) points", category: .boundary)

        // Enable Measure as soon as we have a valid polygon (Bug 3).
        // Validation is non-blocking — shown as warnings only.
        if normalizedBoundaryPoints.count >= 3 {
            CrashLogger.shared.log("didFinalizeBoundary: setting boundaryFinalized=true", category: .boundary)
            boundaryFinalized = true
            CrashLogger.shared.log("didFinalizeBoundary: boundaryFinalized set OK", category: .boundary)
        } else {
            CrashLogger.shared.log("didFinalizeBoundary: too few points: \(normalizedBoundaryPoints.count)", category: .boundary, level: .warning)
        }

        CrashLogger.shared.log("didFinalizeBoundary: calling BoundaryValidator.validate()", category: .boundary)
        let result = BoundaryValidator.validate(points: normalizedBoundaryPoints)
        CrashLogger.shared.log("didFinalizeBoundary: validate returned isValid=\(result.isValid) errors=\(result.errors.count)", category: .boundary)
        validationErrors = result.errors
        CrashLogger.shared.log("didFinalizeBoundary: validationErrors set OK", category: .boundary)
        if !result.errors.isEmpty {
            CrashLogger.shared.log("Boundary validation warnings: \(result.errors.map(\.localizedDescription))", category: .boundary, level: .warning)
        }
        CrashLogger.shared.log("didFinalizeBoundary: COMPLETE", category: .boundary)
    }

    /// Auto-finalize an auto-segmented boundary with relaxed validation.
    /// Vision's contour detector produces valid closed polygons, so we
    /// skip strict self-intersection and area checks that can false-positive
    /// on machine-generated contours.
    func autoFinalizeBoundary(_ points: [CGPoint], in geometry: ImageViewGeometry) {
        CrashLogger.shared.log("autoFinalizeBoundary: \(points.count) points", category: .boundary)
        normalizedBoundaryPoints = points.map { geometry.viewToSensorNormalized($0) }

        guard normalizedBoundaryPoints.count >= 3 else {
            CrashLogger.shared.log("autoFinalizeBoundary: too few points \(normalizedBoundaryPoints.count)", category: .boundary, level: .warning)
            validationErrors = [.tooFewPoints(count: normalizedBoundaryPoints.count)]
            return
        }

        validationErrors = []
        boundaryFinalized = true
        CrashLogger.shared.log("autoFinalizeBoundary: COMPLETE — boundaryFinalized=true", category: .boundary)
    }

    /// Clears boundary state without changing drawingMode.
    /// Called by the VC when switching modes — the mode is owned by the
    /// segmented control, not by the clear action. (Bug 1 fix)
    func clearBoundaryKeepingMode() {
        normalizedBoundaryPoints = []
        boundaryFinalized = false
        validationErrors = []
        normalizedTapPoint = nil
        tapPoint = nil
        boundaryWasAutoSeeded = false
        segmenterModelId = nil
        error = nil
    }

    /// Full clear for the explicit "Clear" button. Does not hardcode
    /// a specific mode — the VC's segmented control owns mode selection.
    func clearBoundary() {
        clearBoundaryKeepingMode()
    }

    // MARK: - Compute Measurements

    /// Run the full measurement pipeline on-device.
    /// Called when nurse confirms the boundary.
    func computeMeasurements(
        patientId: String,
        nurseId: String,
        facilityId: String,
        exudateAmount: ExudateAmount,
        tissueType: TissueType
    ) {
        guard boundaryFinalized else {
            CrashLogger.shared.log("computeMeasurements called but boundary not finalized", category: .measurement, level: .warning)
            return
        }
        CrashLogger.shared.log("Starting measurement pipeline — \(normalizedBoundaryPoints.count) boundary points", category: .measurement)
        isComputing = true

        Task { @MainActor in
            do {
                // 1. Build CaptureData from snapshot
                CrashLogger.shared.log("Step 1: Building CaptureData from snapshot", category: .measurement)
                let captureData = buildCaptureData()
                CrashLogger.shared.logDiagnostics("CaptureData", category: .measurement, data: [
                    "vertexCount": captureData.vertexCount,
                    "faceCount": captureData.faceCount,
                    "imageWidth": captureData.imageWidth,
                    "imageHeight": captureData.imageHeight,
                    "depthWidth": captureData.depthWidth,
                    "depthHeight": captureData.depthHeight,
                    "meshVerticesDataSize": captureData.meshVerticesData.count,
                    "meshFacesDataSize": captureData.meshFacesData.count,
                    "depthMapDataSize": captureData.depthMapData.count,
                ])

                // 2. Project 2D boundary onto 3D mesh (with confidence filtering)
                CrashLogger.shared.log("Step 2: Projecting 2D boundary → 3D mesh", category: .boundary)
                let projection = try BoundaryProjector.project(
                    points2D: normalizedBoundaryPoints,
                    imageWidth: snapshot.imageWidth,
                    imageHeight: snapshot.imageHeight,
                    intrinsics: snapshot.cameraIntrinsics,
                    cameraTransform: snapshot.cameraTransform,
                    vertices: snapshot.vertices,
                    faces: snapshot.faces,
                    depthMap: snapshot.depthMap,
                    depthWidth: snapshot.depthWidth,
                    depthHeight: snapshot.depthHeight,
                    confidenceMap: snapshot.confidenceMap
                )
                CrashLogger.shared.logDiagnostics("Projection Result", category: .boundary, data: [
                    "projectedPoints": projection.projectedPoints3D.count,
                    "meshHitRate": String(format: "%.2f", projection.meshHitRate),
                    "meanDepthConfidence": String(format: "%.2f", projection.meanDepthConfidence),
                ])

                // 3. Build boundary model.
                // An auto-seeded boundary keeps its `.autoVision` source even
                // if the nurse then hand-edited vertices — this matches the
                // audit-trail design (all AI-assisted boundaries are flagged).
                let source: BoundarySource = boundaryWasAutoSeeded ? .autoVision : .nurseDrawn
                CrashLogger.shared.log("Step 3: Building WoundBoundary (source=\(source), mode=\(drawingMode))", category: .boundary)
                let boundary = WoundBoundary(
                    boundaryType: drawingMode == .freeform ? .freeform : .polygon,
                    source: source,
                    points2D: normalizedBoundaryPoints,
                    projectedPoints3D: projection.projectedPoints3D,
                    tapPoint: normalizedTapPoint
                )

                // Combine pre-capture quality with post-projection stats
                let combinedQuality: CaptureQualityScore? = qualityScoreSnapshot.map { pre in
                    CaptureQualityScore(
                        trackingStableSeconds: pre.trackingStableSeconds,
                        captureDistanceM: pre.captureDistanceM,
                        meshVertexCount: pre.meshVertexCount,
                        meanDepthConfidence: projection.meanDepthConfidence,
                        meshHitRate: projection.meshHitRate,
                        angularVelocityRadPerSec: pre.angularVelocityRadPerSec
                    )
                } ?? CaptureQualityScore(
                    trackingStableSeconds: 0,
                    captureDistanceM: 0,
                    meshVertexCount: snapshot.vertices.count,
                    meanDepthConfidence: projection.meanDepthConfidence,
                    meshHitRate: projection.meshHitRate,
                    angularVelocityRadPerSec: 0
                )

                // 4. Run measurement engine — passes camera params + quality
                CrashLogger.shared.log("Step 4: Running MeshMeasurementEngine.measure()", category: .measurement)
                let measurement = try measurementEngine.measure(
                    captureData: captureData,
                    boundary: boundary,
                    qualityScore: combinedQuality
                )
                CrashLogger.shared.logDiagnostics("Measurement Output", category: .measurement, data: [
                    "areaCm2": measurement.areaCm2,
                    "lengthMm": measurement.lengthMm,
                    "widthMm": measurement.widthMm,
                    "maxDepthMm": measurement.maxDepthMm,
                    "meanDepthMm": measurement.meanDepthMm,
                    "volumeMl": measurement.volumeMl,
                    "perimeterMm": measurement.perimeterMm,
                    "processingTimeMs": measurement.processingTimeMs,
                ])

                // 5. Compute PUSH score
                CrashLogger.shared.log("Step 5: Computing PUSH score", category: .measurement)
                let pushScore = PUSHScoreCalculator.computeScore(
                    lengthMm: measurement.lengthMm,
                    widthMm: measurement.widthMm,
                    exudateAmount: exudateAmount,
                    tissueType: tissueType
                )
                CrashLogger.shared.log("PUSH score: \(pushScore.totalScore)", category: .measurement)

                // 6. Assemble WoundScan
                CrashLogger.shared.log("Step 6: Assembling WoundScan", category: .measurement)
                let scan = WoundScan(
                    patientId: patientId,
                    nurseId: nurseId,
                    facilityId: facilityId,
                    capturedAt: snapshot.timestamp,
                    captureData: captureData,
                    nurseBoundary: boundary,
                    primaryMeasurement: measurement,
                    pushScore: pushScore
                )

                isComputing = false
                CrashLogger.shared.log("Measurement pipeline completed successfully", category: .measurement)
                onMeasurementComplete?(scan)

            } catch {
                isComputing = false
                CrashLogger.shared.error("Measurement pipeline FAILED", category: .measurement, error: error)
                self.error = "Measurement failed: \(error.localizedDescription)"
            }
        }
    }

    /// Trigger measurement with default PUSH values for the auto-flow.
    func computeMeasurementsWithDefaults() {
        computeMeasurements(
            patientId: "patient-001",
            nurseId: "nurse-001",
            facilityId: "facility-001",
            exudateAmount: .none,
            tissueType: .granulation
        )
    }

    // MARK: - Geometry Helpers

    /// Shoelace formula for polygon area.
    private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var area: CGFloat = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        return abs(area) / 2
    }

    // MARK: - Build CaptureData

    private func buildCaptureData() -> CaptureData {
        CrashLogger.shared.log("buildCaptureData: vertices=\(snapshot.vertices.count) faces=\(snapshot.faces.count) normals=\(snapshot.normals.count)", category: .measurement)
        // Pack vertices into Data — extract x,y,z individually.
        // SIMD3<Float> has 16-byte stride (backed by SIMD4 storage),
        // but CaptureData.unpackVertices() expects tightly-packed
        // 12-byte (3 × Float) triples. Using withUnsafeBytes(of:)
        // on the whole SIMD3 would write 16 bytes including padding.
        var verticesData = Data()
        verticesData.reserveCapacity(snapshot.vertices.count * 12)
        for v in snapshot.vertices {
            var x = v.x; var y = v.y; var z = v.z
            withUnsafeBytes(of: &x) { verticesData.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { verticesData.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { verticesData.append(contentsOf: $0) }
        }

        // Pack faces — same SIMD3<UInt32> padding issue.
        var facesData = Data()
        facesData.reserveCapacity(snapshot.faces.count * 12)
        for f in snapshot.faces {
            var x = f.x; var y = f.y; var z = f.z
            withUnsafeBytes(of: &x) { facesData.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { facesData.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { facesData.append(contentsOf: $0) }
        }

        // Pack normals — same SIMD3<Float> padding issue.
        var normalsData = Data()
        normalsData.reserveCapacity(snapshot.normals.count * 12)
        for n in snapshot.normals {
            var x = n.x; var y = n.y; var z = n.z
            withUnsafeBytes(of: &x) { normalsData.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { normalsData.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { normalsData.append(contentsOf: $0) }
        }

        // Pack depth map into Data (Float is 4 bytes — no padding issue)
        var depthData = Data()
        depthData.reserveCapacity(snapshot.depthMap.count * 4)
        for d in snapshot.depthMap {
            var depth = d
            withUnsafeBytes(of: &depth) { depthData.append(contentsOf: $0) }
        }

        // Pack confidence map into Data
        let confidenceData = Data(snapshot.confidenceMap)

        // Pack intrinsics (column-major)
        let m = snapshot.cameraIntrinsics
        let intrinsics: [Float] = [
            m[0][0], m[0][1], m[0][2],
            m[1][0], m[1][1], m[1][2],
            m[2][0], m[2][1], m[2][2],
        ]

        // Pack transform (column-major)
        let t = snapshot.cameraTransform
        let transform: [Float] = [
            t[0][0], t[0][1], t[0][2], t[0][3],
            t[1][0], t[1][1], t[1][2], t[1][3],
            t[2][0], t[2][1], t[2][2], t[2][3],
            t[3][0], t[3][1], t[3][2], t[3][3],
        ]

        return CaptureData(
            rgbImageData: snapshot.rgbImageData,
            imageWidth: snapshot.imageWidth,
            imageHeight: snapshot.imageHeight,
            depthMapData: depthData,
            depthWidth: snapshot.depthWidth,
            depthHeight: snapshot.depthHeight,
            confidenceMapData: confidenceData,
            meshVerticesData: verticesData,
            meshFacesData: facesData,
            meshNormalsData: normalsData,
            vertexCount: snapshot.vertices.count,
            faceCount: snapshot.faces.count,
            cameraIntrinsics: intrinsics,
            cameraTransform: transform,
            deviceModel: snapshot.deviceModel,
            lidarAvailable: true
        )
    }
}
