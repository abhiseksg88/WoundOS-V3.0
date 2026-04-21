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

    // MARK: - Navigation

    var onSaveComplete: (() -> Void)?

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

    init(scan: WoundScan, storage: StorageProviderProtocol, uploadManager: UploadManager) {
        self.scan = scan
        self.storage = storage
        self.uploadManager = uploadManager
    }

    // MARK: - Save & Upload

    func saveAndUpload() {
        isSaving = true

        Task { @MainActor in
            do {
                try await storage.saveScan(scan)
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
