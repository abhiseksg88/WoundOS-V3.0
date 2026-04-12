import Foundation

// MARK: - FWA Signal

/// Fraud, Waste & Abuse detection signals for a scan.
/// Computed on the backend by the FWA pipeline.
public struct FWASignal: Codable, Sendable, Equatable {

    /// Nurse's historical baseline IoU agreement with SAM (0...1)
    public let nurseBaselineAgreement: Double

    /// Whether this wound's size is a statistical outlier for this nurse
    public let woundSizeOutlier: Bool

    /// Risk score for copy-paste measurement patterns (0...1)
    public let copyPasteRisk: Double

    /// How consistent this wound is with its longitudinal history (0...1, 1 = consistent)
    public let longitudinalConsistency: Double

    /// Overall FWA risk score (0...1, higher = more suspicious)
    public let overallRiskScore: Double

    /// Specific flags triggered
    public let triggeredFlags: [FWAFlag]

    /// When this analysis was computed
    public let computedAt: Date

    public init(
        nurseBaselineAgreement: Double,
        woundSizeOutlier: Bool,
        copyPasteRisk: Double,
        longitudinalConsistency: Double,
        overallRiskScore: Double,
        triggeredFlags: [FWAFlag] = [],
        computedAt: Date = Date()
    ) {
        self.nurseBaselineAgreement = nurseBaselineAgreement
        self.woundSizeOutlier = woundSizeOutlier
        self.copyPasteRisk = copyPasteRisk
        self.longitudinalConsistency = longitudinalConsistency
        self.overallRiskScore = overallRiskScore
        self.triggeredFlags = triggeredFlags
        self.computedAt = computedAt
    }
}

// MARK: - FWA Flag

public enum FWAFlag: String, Codable, Sendable {
    case lowAIAgreement = "low_ai_agreement"
    case woundSizeOutlier = "wound_size_outlier"
    case suspectedCopyPaste = "suspected_copy_paste"
    case impossibleHealing = "impossible_healing"
    case impossibleDeterioration = "impossible_deterioration"
    case imageReuse = "image_reuse"
    case metadataMismatch = "metadata_mismatch"
    case abnormalScanFrequency = "abnormal_scan_frequency"
}
