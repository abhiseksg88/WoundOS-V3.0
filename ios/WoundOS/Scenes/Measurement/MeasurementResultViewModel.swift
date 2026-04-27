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
        UIImage(data: scan.captureData.rgbImageData)
    }

    /// Boundary points for the overlay (normalized 0...1 → CGPoint)
    var boundaryPointsCG: [CGPoint] {
        scan.nurseBoundary.points2D.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    }

    // MARK: - Formatted Values (matching screenshot style: value + unit separate)

    var areaValue: String {
        String(format: "%.2f", scan.primaryMeasurement.areaCm2)
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
                CrashLogger.shared.log("Scan saved locally. Starting upload…", category: .storage)
                isUploading = true
                await uploadManager.enqueueUpload(scan: scan)
                CrashLogger.shared.log("Upload enqueued successfully", category: .network)
                isSaving = false
                isUploading = false
                onSaveComplete?()
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
