import Foundation
import Combine
import WoundCore

// MARK: - Scan Detail View Model

final class ScanDetailViewModel: ObservableObject {

    @Published var scan: WoundScan

    init(scan: WoundScan) {
        self.scan = scan
    }

    // MARK: - Formatted Measurements

    var measurements: [(label: String, value: String)] {
        let m = scan.primaryMeasurement
        return [
            ("Area", String(format: "%.1f cm²", m.areaCm2)),
            ("Max Depth", String(format: "%.1f mm", m.maxDepthMm)),
            ("Mean Depth", String(format: "%.1f mm", m.meanDepthMm)),
            ("Volume", String(format: "%.2f mL", m.volumeMl)),
            ("Length", String(format: "%.1f mm", m.lengthMm)),
            ("Width", String(format: "%.1f mm", m.widthMm)),
            ("Perimeter", String(format: "%.1f mm", m.perimeterMm)),
        ]
    }

    // MARK: - PUSH Score

    var pushScoreValue: Int {
        scan.pushScore.totalScore
    }

    var pushBreakdown: String {
        let lw = scan.pushScore.lengthTimesWidthSubScore
        let ex = scan.pushScore.exudateAmount.subScore
        let tt = scan.pushScore.tissueType.subScore
        return "L×W: \(lw)  Exudate: \(ex)  Tissue: \(tt)"
    }

    var pushDetails: [(label: String, value: String)] {
        [
            ("L × W", String(format: "%.1f cm² (sub-score: %d)", scan.pushScore.lengthTimesWidthCm2, scan.pushScore.lengthTimesWidthSubScore)),
            ("Exudate", "\(scan.pushScore.exudateAmount.displayName) (sub-score: \(scan.pushScore.exudateAmount.subScore))"),
            ("Tissue Type", "\(scan.pushScore.tissueType.displayName) (sub-score: \(scan.pushScore.tissueType.subScore))"),
        ]
    }

    // MARK: - Shadow Comparison (if available)

    var hasShadowData: Bool {
        scan.shadowMeasurement != nil
    }

    var shadowComparison: [(label: String, nurse: String, ai: String)] {
        guard let shadow = scan.shadowMeasurement else { return [] }
        let primary = scan.primaryMeasurement
        return [
            ("Area", String(format: "%.1f cm²", primary.areaCm2), String(format: "%.1f cm²", shadow.areaCm2)),
            ("Max Depth", String(format: "%.1f mm", primary.maxDepthMm), String(format: "%.1f mm", shadow.maxDepthMm)),
            ("Volume", String(format: "%.2f mL", primary.volumeMl), String(format: "%.2f mL", shadow.volumeMl)),
            ("Length", String(format: "%.1f mm", primary.lengthMm), String(format: "%.1f mm", shadow.lengthMm)),
            ("Width", String(format: "%.1f mm", primary.widthMm), String(format: "%.1f mm", shadow.widthMm)),
        ]
    }

    // MARK: - Agreement Metrics (if available)

    var agreementMetrics: [(label: String, value: String)]? {
        guard let a = scan.agreementMetrics else { return nil }
        return [
            ("IoU", String(format: "%.1f%%", a.iou * 100)),
            ("Dice", String(format: "%.1f%%", a.diceCoefficient * 100)),
            ("Area Delta", String(format: "%.1f%%", a.areaDeltaPercent)),
            ("Depth Delta", String(format: "%.1f mm", a.depthDeltaMm)),
            ("Centroid Offset", String(format: "%.1f mm", a.centroidDisplacementMm)),
        ]
    }

    var isFlagged: Bool {
        scan.agreementMetrics?.isFlagged ?? false
    }

    var flagReasons: [String] {
        scan.agreementMetrics?.flagReasons ?? []
    }

    // MARK: - Clinical Summary (if available)

    var clinicalSummary: ClinicalSummary? {
        scan.clinicalSummary
    }

    // MARK: - Capture Quality

    var hasQualityScore: Bool {
        scan.primaryMeasurement.qualityScore != nil
    }

    var qualityTier: String? {
        scan.primaryMeasurement.qualityScore?.tier.displayName
    }

    var qualityRows: [(label: String, value: String)] {
        guard let q = scan.primaryMeasurement.qualityScore else { return [] }
        return [
            ("Tracking Stable", String(format: "%.1f s", q.trackingStableSeconds)),
            ("Capture Distance", String(format: "%.0f cm", q.captureDistanceM * 100)),
            ("Mesh Vertices", "\(q.meshVertexCount)"),
            ("Depth Confidence", String(format: "%.2f / 2.0", q.meanDepthConfidence)),
            ("Mesh Hit Rate", String(format: "%.0f%%", q.meshHitRate * 100)),
            ("Motion (rad/s)", String(format: "%.3f", q.angularVelocityRadPerSec)),
        ]
    }

    // MARK: - Upload Status

    var uploadStatusText: String {
        switch scan.uploadStatus {
        case .pending: return "Pending upload"
        case .uploading: return "Uploading..."
        case .uploaded: return "Uploaded, processing..."
        case .processed: return "Processed"
        case .failed: return "Upload failed"
        }
    }
}
