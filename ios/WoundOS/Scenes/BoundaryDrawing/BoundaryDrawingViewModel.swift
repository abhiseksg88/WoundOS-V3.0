import Foundation
import Combine
import simd
import WoundCore
import WoundBoundary
import WoundMeasurement

// MARK: - Boundary Drawing View Model

final class BoundaryDrawingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var drawingMode: DrawingMode = .tapPoint
    @Published var tapPoint: CGPoint?
    @Published var boundaryFinalized = false
    @Published var isComputing = false
    @Published var error: String?
    @Published var validationErrors: [BoundaryValidationError] = []

    // MARK: - Navigation

    var onMeasurementComplete: ((WoundScan) -> Void)?

    // MARK: - Data

    let snapshot: CaptureSnapshot
    private let measurementEngine: MeshMeasurementEngine
    private var normalizedTapPoint: SIMD2<Float>?
    private var normalizedBoundaryPoints: [SIMD2<Float>] = []

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
        }
    }

    // MARK: - Init

    init(snapshot: CaptureSnapshot, measurementEngine: MeshMeasurementEngine) {
        self.snapshot = snapshot
        self.measurementEngine = measurementEngine
    }

    // MARK: - Tap Point

    func didPlaceTapPoint(_ point: CGPoint, in viewSize: CGSize) {
        tapPoint = point
        normalizedTapPoint = SIMD2<Float>(
            Float(point.x / viewSize.width),
            Float(point.y / viewSize.height)
        )
        // Advance to polygon drawing mode
        drawingMode = .polygon
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

                // 2. Project 2D boundary onto 3D mesh
                let projectedPoints = try BoundaryProjector.project(
                    points2D: normalizedBoundaryPoints,
                    imageWidth: snapshot.imageWidth,
                    imageHeight: snapshot.imageHeight,
                    intrinsics: snapshot.cameraIntrinsics,
                    cameraTransform: snapshot.cameraTransform,
                    vertices: snapshot.vertices,
                    faces: snapshot.faces,
                    depthMap: snapshot.depthMap,
                    depthWidth: snapshot.depthWidth,
                    depthHeight: snapshot.depthHeight
                )

                // 3. Build boundary model
                let boundary = WoundBoundary(
                    boundaryType: drawingMode == .freeform ? .freeform : .polygon,
                    source: .nurseDrawn,
                    points2D: normalizedBoundaryPoints,
                    projectedPoints3D: projectedPoints,
                    tapPoint: normalizedTapPoint
                )

                // 4. Run measurement engine
                let measurement = try measurementEngine.computeMeasurements(
                    boundary: boundary,
                    vertices: snapshot.vertices,
                    faces: snapshot.faces,
                    normals: snapshot.normals
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
