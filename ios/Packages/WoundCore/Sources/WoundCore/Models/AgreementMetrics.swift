import Foundation

// MARK: - Agreement Metrics

/// Comparison between nurse-drawn boundary and SAM 2 AI boundary.
/// Both boundaries are measured against the same frozen ARKit mesh,
/// so deltas isolate the boundary difference, not capture noise.
public struct AgreementMetrics: Codable, Sendable, Equatable {

    /// Intersection over Union of the two binary masks (0...1)
    public let iou: Double

    /// Dice coefficient: 2|A∩B| / (|A|+|B|)  (0...1)
    public let diceCoefficient: Double

    /// |nurse_area − sam_area| / avg(nurse_area, sam_area) × 100
    public let areaDeltaPercent: Double

    /// |nurse_depth − sam_depth| in mm
    public let depthDeltaMm: Double

    /// |nurse_volume − sam_volume| in mL
    public let volumeDeltaMl: Double

    /// 3D Euclidean distance between boundary centroids in mm
    public let centroidDisplacementMm: Double

    /// SAM 2 model confidence score for its segmentation (0...1)
    public let samConfidence: Double

    /// Model version that produced the SAM boundary
    public let samModelVersion: String

    /// Computed at this time
    public let computedAt: Date

    /// Whether this scan is flagged for clinical review
    public var isFlagged: Bool {
        iou < 0.7
            || areaDeltaPercent > 20.0
            || depthDeltaMm > 2.0
            || centroidDisplacementMm > 20.0
    }

    /// Human-readable reasons this scan was flagged
    public var flagReasons: [String] {
        var reasons = [String]()
        if iou < 0.7 {
            reasons.append("Low boundary agreement (IoU: \(String(format: "%.2f", iou)))")
        }
        if areaDeltaPercent > 20.0 {
            reasons.append("Area differs by \(String(format: "%.1f", areaDeltaPercent))%")
        }
        if depthDeltaMm > 2.0 {
            reasons.append("Depth differs by \(String(format: "%.1f", depthDeltaMm)) mm")
        }
        if centroidDisplacementMm > 20.0 {
            reasons.append("Boundary centers \(String(format: "%.1f", centroidDisplacementMm)) mm apart")
        }
        return reasons
    }

    public init(
        iou: Double,
        diceCoefficient: Double,
        areaDeltaPercent: Double,
        depthDeltaMm: Double,
        volumeDeltaMl: Double,
        centroidDisplacementMm: Double,
        samConfidence: Double,
        samModelVersion: String,
        computedAt: Date = Date()
    ) {
        self.iou = iou
        self.diceCoefficient = diceCoefficient
        self.areaDeltaPercent = areaDeltaPercent
        self.depthDeltaMm = depthDeltaMm
        self.volumeDeltaMl = volumeDeltaMl
        self.centroidDisplacementMm = centroidDisplacementMm
        self.samConfidence = samConfidence
        self.samModelVersion = samModelVersion
        self.computedAt = computedAt
    }
}
