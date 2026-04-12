import Foundation
import WoundCore

// MARK: - PUSH Score Calculator

/// Computes the NPUAP PUSH Tool 3.0 score from wound measurements
/// and nurse-observed clinical inputs (exudate amount, tissue type).
public enum PUSHScoreCalculator {

    /// Compute the PUSH 3.0 score.
    /// - Parameters:
    ///   - lengthMm: Wound length in mm (from DimensionCalculator)
    ///   - widthMm: Wound width in mm (from DimensionCalculator)
    ///   - exudateAmount: Nurse-observed exudate amount
    ///   - tissueType: Nurse-observed wound bed tissue type
    /// - Returns: Complete PUSHScore
    public static func computeScore(
        lengthMm: Double,
        widthMm: Double,
        exudateAmount: ExudateAmount,
        tissueType: TissueType
    ) -> PUSHScore {
        // PUSH uses length × width in cm²
        let lengthCm = lengthMm / 10.0
        let widthCm = widthMm / 10.0
        let lxw = lengthCm * widthCm

        return PUSHScore(
            lengthTimesWidthCm2: lxw,
            exudateAmount: exudateAmount,
            tissueType: tissueType
        )
    }
}
