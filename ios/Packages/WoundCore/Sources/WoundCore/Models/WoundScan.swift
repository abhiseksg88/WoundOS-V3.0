import Foundation
import simd

// MARK: - Wound Scan

/// Top-level aggregate for a single wound scan session.
/// One scan = one capture event by one nurse for one patient.
/// Contains the frozen capture data, nurse boundary, primary measurements,
/// and optionally the shadow AI measurements and agreement metrics
/// once the backend has processed it.
public struct WoundScan: Codable, Sendable, Identifiable {

    /// Unique scan identifier
    public let id: UUID

    /// Patient this wound belongs to
    public let patientId: String

    /// Nurse who performed the capture and drew the boundary
    public let nurseId: String

    /// Facility where the scan was performed
    public let facilityId: String

    /// When the ARKit frame was frozen (capture moment)
    public let capturedAt: Date

    /// All frozen ARKit data (RGB, depth, mesh, camera)
    public let captureData: CaptureData

    /// Nurse-drawn wound boundary (primary path)
    public let nurseBoundary: WoundBoundary

    /// Primary measurement from nurse boundary + frozen mesh (on-device)
    public let primaryMeasurement: WoundMeasurement

    /// PUSH 3.0 score (includes nurse-observed exudate and tissue type)
    public let pushScore: PUSHScore

    // MARK: - Backend-populated fields

    /// SAM 2 boundary from shadow path (populated by backend)
    public var shadowBoundary: WoundBoundary?

    /// Measurement from SAM 2 boundary + same frozen mesh (populated by backend)
    public var shadowMeasurement: WoundMeasurement?

    /// Agreement between nurse and SAM 2 (populated by backend)
    public var agreementMetrics: AgreementMetrics?

    /// Review status (populated by backend when flagged)
    public var reviewStatus: ReviewStatus

    /// FWA signals (populated by backend pipeline)
    public var fwaSignals: FWASignal?

    /// Clinical summary (populated by backend via Claude)
    public var clinicalSummary: ClinicalSummary?

    /// Upload status
    public var uploadStatus: UploadStatus

    // MARK: - Clinical Platform fields (Phase 5)

    /// Link to Wound entity in WoundClinical (nil for legacy scans)
    public var woundId: UUID?

    /// Link to Encounter entity in WoundClinical (nil for legacy scans)
    public var encounterId: UUID?

    /// Denormalized display string, e.g. "Left Heel" (nil for legacy scans)
    public var anatomicalLocation: String?

    public init(
        id: UUID = UUID(),
        patientId: String,
        nurseId: String,
        facilityId: String,
        capturedAt: Date = Date(),
        captureData: CaptureData,
        nurseBoundary: WoundBoundary,
        primaryMeasurement: WoundMeasurement,
        pushScore: PUSHScore,
        shadowBoundary: WoundBoundary? = nil,
        shadowMeasurement: WoundMeasurement? = nil,
        agreementMetrics: AgreementMetrics? = nil,
        reviewStatus: ReviewStatus = ReviewStatus(),
        fwaSignals: FWASignal? = nil,
        clinicalSummary: ClinicalSummary? = nil,
        uploadStatus: UploadStatus = .pending,
        woundId: UUID? = nil,
        encounterId: UUID? = nil,
        anatomicalLocation: String? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.nurseId = nurseId
        self.facilityId = facilityId
        self.capturedAt = capturedAt
        self.captureData = captureData
        self.nurseBoundary = nurseBoundary
        self.primaryMeasurement = primaryMeasurement
        self.pushScore = pushScore
        self.shadowBoundary = shadowBoundary
        self.shadowMeasurement = shadowMeasurement
        self.agreementMetrics = agreementMetrics
        self.reviewStatus = reviewStatus
        self.fwaSignals = fwaSignals
        self.clinicalSummary = clinicalSummary
        self.uploadStatus = uploadStatus
        self.woundId = woundId
        self.encounterId = encounterId
        self.anatomicalLocation = anatomicalLocation
    }
}

// MARK: - Upload Status

public enum UploadStatus: String, Codable, Sendable {
    /// Not yet attempted
    case pending
    /// Currently uploading
    case uploading
    /// Successfully uploaded, backend processing
    case uploaded
    /// Backend has completed shadow analysis
    case processed
    /// Upload failed, will retry
    case failed
    /// Upload succeeded but backend processing timed out (scan is safe on server)
    case processingTimeout
}
