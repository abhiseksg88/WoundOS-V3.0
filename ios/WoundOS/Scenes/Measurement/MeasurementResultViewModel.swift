import Foundation
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

    // MARK: - Navigation

    var onSaveComplete: (() -> Void)?

    // MARK: - Dependencies

    private let storage: StorageProviderProtocol
    private let uploadManager: UploadManager

    // MARK: - Formatted Values

    var areaCm2: String {
        String(format: "%.1f cm²", scan.primaryMeasurement.areaCm2)
    }

    var maxDepthMm: String {
        String(format: "%.1f mm", scan.primaryMeasurement.maxDepthMm)
    }

    var meanDepthMm: String {
        String(format: "%.1f mm", scan.primaryMeasurement.meanDepthMm)
    }

    var volumeMl: String {
        String(format: "%.2f mL", scan.primaryMeasurement.volumeMl)
    }

    var lengthMm: String {
        String(format: "%.1f mm", scan.primaryMeasurement.lengthMm)
    }

    var widthMm: String {
        String(format: "%.1f mm", scan.primaryMeasurement.widthMm)
    }

    var perimeterMm: String {
        String(format: "%.1f mm", scan.primaryMeasurement.perimeterMm)
    }

    var pushTotalScore: String {
        "\(scan.pushScore.totalScore) / 17"
    }

    var pushBreakdown: String {
        let lw = scan.pushScore.lengthTimesWidthSubScore
        let ex = scan.pushScore.exudateAmount.subScore
        let tt = scan.pushScore.tissueType.subScore
        return "L×W: \(lw) + Exudate: \(ex) + Tissue: \(tt)"
    }

    var processingTime: String {
        "\(scan.primaryMeasurement.processingTimeMs) ms"
    }

    // MARK: - Init

    init(scan: WoundScan, storage: StorageProviderProtocol, uploadManager: UploadManager) {
        self.scan = scan
        self.storage = storage
        self.uploadManager = uploadManager
    }

    // MARK: - Save & Upload

    /// Save locally and enqueue for background upload.
    func saveAndUpload() {
        isSaving = true

        Task { @MainActor in
            do {
                // Save to local storage
                try await storage.saveScan(scan)

                // Enqueue for background upload
                isUploading = true
                await uploadManager.enqueueUpload(scan: scan)

                isSaving = false
                isUploading = false
                onSaveComplete?()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }

    /// Save locally only (offline mode).
    func saveLocally() {
        isSaving = true

        Task { @MainActor in
            do {
                try await storage.saveScan(scan)
                isSaving = false
                onSaveComplete?()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
