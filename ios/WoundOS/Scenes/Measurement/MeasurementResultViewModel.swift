import Foundation
import UIKit
import Combine
import WoundCore
import WoundNetworking

// MARK: - Measurement Result View Model

final class MeasurementResultViewModel: ObservableObject {

    // MARK: - Published State

    @Published var scan: WoundScan
    @Published var isSaving = false
    @Published var isUploading = false
    @Published var saveError: String?

    // MARK: - Manual Clinical Measurements

    @Published var manualLengthCm: String = ""
    @Published var manualWidthCm: String = ""
    @Published var manualDepthCm: String = ""
    @Published var manualMethod: ManualMethod = .ruler

    enum ManualMethod: String, CaseIterable {
        case ruler = "Ruler"
        case tracing = "Tracing"
        case digital = "Digital"
    }

    // MARK: - Navigation

    var onSaveComplete: (() -> Void)?
    var onContinueToAssessment: (() -> Void)?

    let showContinueToAssessment: Bool

    // MARK: - Dependencies

    private let storage: StorageProviderProtocol
    private let uploadManager: UploadManager

    // MARK: - Wound Image

    var woundImage: UIImage? {
        guard let raw = UIImage(data: scan.captureData.rgbImageData),
              let cg = raw.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .right)
    }

    /// Boundary points for the overlay in display-normalized portrait coordinates (0...1).
    /// points2D are stored in sensor-normalized landscape-right space.
    /// Inverse of ImageViewGeometry.viewToSensorNormalized:
    ///   display_x = sensor_y,  display_y = 1 - sensor_x
    var boundaryPointsCG: [CGPoint] {
        scan.nurseBoundary.points2D.map { CGPoint(x: CGFloat($0.y), y: CGFloat(1.0 - $0.x)) }
    }

    // MARK: - Formatted Values (matching screenshot style: value + unit separate)

    var polygonAreaCm2: Double {
        guard let pts3D = scan.nurseBoundary.projectedPoints3D, pts3D.count >= 3 else { return 0 }
        var nx: Float = 0, ny: Float = 0, nz: Float = 0
        for i in 0..<pts3D.count {
            let c = pts3D[i]
            let n = pts3D[(i + 1) % pts3D.count]
            nx += (c.y - n.y) * (c.z + n.z)
            ny += (c.z - n.z) * (c.x + n.x)
            nz += (c.x - n.x) * (c.y + n.y)
        }
        let areaM2 = Double(sqrt(nx * nx + ny * ny + nz * nz)) / 2.0
        return areaM2 * 10_000.0
    }

    var areaValue: String {
        String(format: "%.2f", polygonAreaCm2)
    }

    var areaUnit: String { "cm²" }

    var perimeterValue: String {
        String(format: "%.2f", scan.primaryMeasurement.perimeterMm / 10.0) // mm → cm
    }

    var perimeterUnit: String { "cm" }

    var lengthValue: String {
        String(format: "%.2f", scan.primaryMeasurement.lengthMm / 10.0)
    }

    var lengthUnit: String { "cm" }

    var widthValue: String {
        String(format: "%.2f", scan.primaryMeasurement.widthMm / 10.0)
    }

    var widthUnit: String { "cm" }

    var maxDepthValue: String {
        String(format: "%.1f", scan.primaryMeasurement.maxDepthMm)
    }

    var maxDepthUnit: String { "mm" }

    var meanDepthValue: String {
        String(format: "%.1f", scan.primaryMeasurement.meanDepthMm)
    }

    var meanDepthUnit: String { "mm" }

    var volumeValue: String {
        String(format: "%.2f", scan.primaryMeasurement.volumeMl)
    }

    var volumeUnit: String { "mL" }

    var pushTotalScore: Int {
        scan.pushScore.totalScore
    }

    var pushBreakdown: String {
        let lw = scan.pushScore.lengthTimesWidthSubScore
        let ex = scan.pushScore.exudateAmount.subScore
        let tt = scan.pushScore.tissueType.subScore
        return "L×W: \(lw)  Exudate: \(ex)  Tissue: \(tt)"
    }

    var processingTime: String {
        "\(scan.primaryMeasurement.processingTimeMs) ms"
    }

    var exudateDisplay: String {
        scan.pushScore.exudateAmount.displayName
    }

    var tissueTypeDisplay: String {
        scan.pushScore.tissueType.displayName
    }

    // MARK: - Area Diagnostics

    func logAreaDiagnostics() {
        let pts2D = scan.nurseBoundary.points2D
        let pts3D = scan.nurseBoundary.projectedPoints3D
        let m = scan.primaryMeasurement

        let first3_2D = pts2D.prefix(3).map { "(\($0.x), \($0.y))" }.joined(separator: ", ")
        let last3_2D = pts2D.suffix(3).map { "(\($0.x), \($0.y))" }.joined(separator: ", ")

        let xVals = pts2D.map(\.x)
        let yVals = pts2D.map(\.y)
        let coordSpace = (xVals.max() ?? 0) <= 1.1 ? "normalized [0,1]" : "pixel coords"

        let pts3DCount = pts3D?.count ?? 0
        let first3_3D = (pts3D ?? []).prefix(3).map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: ", ")
        let last3_3D = (pts3D ?? []).suffix(3).map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: ", ")

        let lengthCm = m.lengthMm / 10.0
        let widthCm = m.widthMm / 10.0
        let lxw = lengthCm * widthCm
        let meshAreaCm2 = m.areaCm2
        let newellAreaCm2 = polygonAreaCm2
        let newellRatio = lxw > 0 ? newellAreaCm2 / lxw : 0
        let meshRatio = newellAreaCm2 > 0 ? meshAreaCm2 / newellAreaCm2 : 0

        let imgW = scan.captureData.imageWidth
        let imgH = scan.captureData.imageHeight

        CrashLogger.shared.logDiagnostics("AREA_DEBUG", category: .measurement, data: [
            "01_pts2D_count": pts2D.count,
            "02_first3_2D": first3_2D,
            "03_last3_2D": last3_2D,
            "04_coordSpace": coordSpace,
            "05_xRange": "\(xVals.min() ?? 0)...\(xVals.max() ?? 0)",
            "06_yRange": "\(yVals.min() ?? 0)...\(yVals.max() ?? 0)",
            "07_pts3D_count": pts3DCount,
            "08_first3_3D": first3_3D,
            "09_last3_3D": last3_3D,
            "10_imageRes": "\(imgW)x\(imgH)",
            "11_lengthCm": String(format: "%.4f", lengthCm),
            "12_widthCm": String(format: "%.4f", widthCm),
            "13_LxW_cm2": String(format: "%.4f", lxw),
            "14_meshAreaCm2": String(format: "%.4f", meshAreaCm2),
            "15_newellAreaCm2": String(format: "%.4f", newellAreaCm2),
            "16_newell_vs_LxW": String(format: "%.4f", newellRatio),
            "17_mesh_vs_newell": String(format: "%.4f", meshRatio),
            "18_maxDepthMm": String(format: "%.2f", m.maxDepthMm),
            "19_meanDepthMm": String(format: "%.2f", m.meanDepthMm),
            "20_perimeterMm": String(format: "%.2f", m.perimeterMm),
        ])
    }

    // MARK: - Init

    init(
        scan: WoundScan,
        storage: StorageProviderProtocol,
        uploadManager: UploadManager,
        showContinueToAssessment: Bool = false
    ) {
        self.scan = scan
        self.storage = storage
        self.uploadManager = uploadManager
        self.showContinueToAssessment = showContinueToAssessment
    }

    // MARK: - Save & Upload

    func saveAndUpload() {
        CrashLogger.shared.log("saveAndUpload() called — scanId=\(scan.id)", category: .storage)
        isSaving = true

        Task { @MainActor in
            do {
                CrashLogger.shared.log("Saving scan to local storage…", category: .storage)
                try await storage.saveScan(scan)
                CrashLogger.shared.log("Scan saved locally. Queuing upload in background.", category: .storage)
                isSaving = false
                onSaveComplete?()

                Task { [scan, uploadManager] in
                    await uploadManager.enqueueUpload(scan: scan)
                    CrashLogger.shared.log("Upload enqueued successfully", category: .network)
                }
            } catch {
                CrashLogger.shared.error("saveAndUpload failed", category: .storage, error: error)
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }

    func saveLocally() {
        CrashLogger.shared.log("saveLocally() called — scanId=\(scan.id)", category: .storage)
        isSaving = true

        Task { @MainActor in
            do {
                try await storage.saveScan(scan)
                CrashLogger.shared.log("Scan saved locally", category: .storage)
                isSaving = false
                onSaveComplete?()
            } catch {
                CrashLogger.shared.error("saveLocally failed", category: .storage, error: error)
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
