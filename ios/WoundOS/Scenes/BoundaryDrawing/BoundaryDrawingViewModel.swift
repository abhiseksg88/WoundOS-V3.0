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
    private var segmenterModelId: String?

    /// The captured RGB image for display
    var capturedImage: UIImage? {
        UIImage(data: snapshot.rgbImageData)
    }

    var instructionText: String {
        switch drawingMode {
        case .tapPoint:
            return "Tap the center of the wound"
        case .polygon:
            return "Tap around the wound edge to place points. Tap near the first point to close."
        case .freeform:
            return "Trace your finger around the wound edge"
        case .auto:
            return autoSegmenterAvailable
                ? "Tap the center of the object — outline will appear automatically"
                : "Auto-detect requires iOS 17. Switch to Polygon or Freeform."
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

    func didPlaceTapPoint(_ point: CGPoint, in viewSize: CGSize) {
        tapPoint = point
        normalizedTapPoint = SIMD2<Float>(
            Float(point.x / viewSize.width),
            Float(point.y / viewSize.height)
        )

        // In .auto mode, the tap is a point prompt for the segmenter. The VC
        // subscribes to `autoSegmentationResult` and seeds the canvas with
        // the resulting polygon. Otherwise, advance to polygon drawing mode.
        if drawingMode == .auto {
            runAutoSegmentation(tapPoint: point, viewSize: viewSize)
        } else {
            drawingMode = .polygon
        }
    }

    // MARK: - Auto Segmentation

    func runAutoSegmentation(tapPoint: CGPoint, viewSize: CGSize) {
        guard let segmenter else {
            error = "Auto-detect is not available on this device."
            return
        }
        guard let image = capturedImage, let cgImage = image.cgImage else {
            error = "Captured image is unavailable."
            return
        }

        // Convert tap from view-local coords to image pixel coords. The
        // image view uses .scaleAspectFit — same letterboxing logic the
        // existing pipeline relies on — so we project through the fit rect.
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let fitRect = aspectFitRect(imageSize: imageSize, in: viewSize)
        guard fitRect.contains(tapPoint) else {
            error = "Tap inside the image area."
            return
        }
        let imageTap = CGPoint(
            x: (tapPoint.x - fitRect.minX) / fitRect.width * imageSize.width,
            y: (tapPoint.y - fitRect.minY) / fitRect.height * imageSize.height
        )

        isAutoSegmenting = true
        Task { @MainActor in
            defer { isAutoSegmenting = false }
            do {
                let result = try await segmenter.segment(
                    image: cgImage,
                    tapPoint: imageTap
                )
                // Project polygon back into view-local coords for the canvas.
                let viewPolygon = result.polygonImageSpace.map { p in
                    CGPoint(
                        x: fitRect.minX + p.x / imageSize.width * fitRect.width,
                        y: fitRect.minY + p.y / imageSize.height * fitRect.height
                    )
                }
                boundaryWasAutoSeeded = true
                segmenterModelId = result.modelIdentifier
                autoSegmentationResult.send(viewPolygon)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let origin = CGPoint(
            x: (viewSize.width - fittedSize.width) / 2,
            y: (viewSize.height - fittedSize.height) / 2
        )
        return CGRect(origin: origin, size: fittedSize)
    }

    // MARK: - Boundary Updates

    func didUpdateBoundary(_ points: [CGPoint], in viewSize: CGSize) {
        normalizedBoundaryPoints = points.map { p in
            SIMD2<Float>(
                Float(p.x / viewSize.width),
                Float(p.y / viewSize.height)
            )
        }
    }

    func didFinalizeBoundary(_ points: [CGPoint], in viewSize: CGSize) {
        normalizedBoundaryPoints = points.map { p in
            SIMD2<Float>(
                Float(p.x / viewSize.width),
                Float(p.y / viewSize.height)
            )
        }

        // Validate
        let result = BoundaryValidator.validate(points: normalizedBoundaryPoints)
        if !result.isValid {
            validationErrors = result.errors
            return
        }

        validationErrors = []
        boundaryFinalized = true
    }

    func clearBoundary() {
        normalizedBoundaryPoints = []
        boundaryFinalized = false
        validationErrors = []
        drawingMode = .tapPoint
        normalizedTapPoint = nil
        tapPoint = nil
        boundaryWasAutoSeeded = false
        segmenterModelId = nil
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
        guard boundaryFinalized else { return }
        isComputing = true

        Task { @MainActor in
            do {
                // 1. Build CaptureData from snapshot
                let captureData = buildCaptureData()

                // 2. Project 2D boundary onto 3D mesh (with confidence filtering)
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

                // 3. Build boundary model.
                // An auto-seeded boundary keeps its `.autoVision` source even
                // if the nurse then hand-edited vertices — this matches the
                // audit-trail design (all AI-assisted boundaries are flagged).
                let source: BoundarySource = boundaryWasAutoSeeded ? .autoVision : .nurseDrawn
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
                let measurement = try measurementEngine.measure(
                    captureData: captureData,
                    boundary: boundary,
                    qualityScore: combinedQuality
                )

                // 5. Compute PUSH score
                let pushScore = PUSHScoreCalculator.computeScore(
                    lengthMm: measurement.lengthMm,
                    widthMm: measurement.widthMm,
                    exudateAmount: exudateAmount,
                    tissueType: tissueType
                )

                // 6. Assemble WoundScan
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
                onMeasurementComplete?(scan)

            } catch {
                isComputing = false
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Build CaptureData

    private func buildCaptureData() -> CaptureData {
        // Pack vertices into Data
        var verticesData = Data()
        for v in snapshot.vertices {
            var vertex = v
            withUnsafeBytes(of: &vertex) { verticesData.append(contentsOf: $0) }
        }

        // Pack faces into Data
        var facesData = Data()
        for f in snapshot.faces {
            var face = f
            withUnsafeBytes(of: &face) { facesData.append(contentsOf: $0) }
        }

        // Pack normals into Data
        var normalsData = Data()
        for n in snapshot.normals {
            var normal = n
            withUnsafeBytes(of: &normal) { normalsData.append(contentsOf: $0) }
        }

        // Pack depth map into Data
        var depthData = Data()
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
