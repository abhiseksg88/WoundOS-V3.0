import Foundation
import SwiftData

// MARK: - Capture Bundle Entity

/// SwiftData model for persisting V5 CaptureBundle data.
/// Uses external storage for the large binary blob to avoid
/// bloating the SQLite database.
@Model
final class CaptureBundleEntity {
    @Attribute(.unique) var captureId: UUID
    var capturedAt: Date
    var captureMode: String   // CaptureMode.rawValue
    var qualityTier: String   // QualityTier.rawValue

    /// The full CaptureBundle encoded as JSON. Stored externally
    /// because it includes JPEG + packed mesh data (typically 5-50 MB).
    @Attribute(.externalStorage) var captureBundleData: Data

    // Denormalized metadata for efficient querying
    var deviceModel: String
    var lidarAvailable: Bool
    var confidenceScore: Float

    /// Linked to a WoundScan after scan assembly (nil for orphans)
    var scanId: UUID?

    init(
        captureId: UUID,
        capturedAt: Date,
        captureMode: String,
        qualityTier: String,
        captureBundleData: Data,
        deviceModel: String,
        lidarAvailable: Bool,
        confidenceScore: Float,
        scanId: UUID? = nil
    ) {
        self.captureId = captureId
        self.capturedAt = capturedAt
        self.captureMode = captureMode
        self.qualityTier = qualityTier
        self.captureBundleData = captureBundleData
        self.deviceModel = deviceModel
        self.lidarAvailable = lidarAvailable
        self.confidenceScore = confidenceScore
        self.scanId = scanId
    }
}
