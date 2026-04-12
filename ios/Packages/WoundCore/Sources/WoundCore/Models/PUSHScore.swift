import Foundation

// MARK: - PUSH Score (Pressure Ulcer Scale for Healing 3.0)

/// NPUAP PUSH Tool 3.0 scoring model.
/// Total score = Length×Width sub-score + Exudate sub-score + Tissue Type sub-score.
/// Range: 0–17. Lower is better; 0 = healed.
public struct PUSHScore: Codable, Sendable, Equatable {

    /// Length × Width in cm² (from measurement)
    public let lengthTimesWidthCm2: Double

    /// Sub-score for length × width (0–10)
    public let lengthTimesWidthSubScore: Int

    /// Exudate amount observed by the nurse
    public let exudateAmount: ExudateAmount

    /// Tissue type observed by the nurse
    public let tissueType: TissueType

    /// Total PUSH 3.0 score (0–17)
    public var totalScore: Int {
        lengthTimesWidthSubScore + exudateAmount.subScore + tissueType.subScore
    }

    public init(lengthTimesWidthCm2: Double, exudateAmount: ExudateAmount, tissueType: TissueType) {
        self.lengthTimesWidthCm2 = lengthTimesWidthCm2
        self.lengthTimesWidthSubScore = Self.lookupLengthWidthSubScore(lengthTimesWidthCm2)
        self.exudateAmount = exudateAmount
        self.tissueType = tissueType
    }

    // MARK: - PUSH 3.0 Length × Width Lookup Table

    /// Maps Length × Width (cm²) to sub-score per NPUAP PUSH 3.0 table.
    public static func lookupLengthWidthSubScore(_ lw: Double) -> Int {
        switch lw {
        case 0:                     return 0
        case ..<0.3:                return 1
        case 0.3..<0.7:             return 2
        case 0.7..<1.1:             return 3
        case 1.1..<2.1:             return 4
        case 2.1..<3.1:             return 5
        case 3.1..<4.1:             return 6
        case 4.1..<8.1:             return 7
        case 8.1..<12.1:            return 8
        case 12.1..<24.1:           return 9
        default:                    return 10  // > 24 cm²
        }
    }
}

// MARK: - Exudate Amount

public enum ExudateAmount: String, Codable, Sendable, CaseIterable {
    case none
    case light
    case moderate
    case heavy

    public var subScore: Int {
        switch self {
        case .none:     return 0
        case .light:    return 1
        case .moderate: return 2
        case .heavy:    return 3
        }
    }

    public var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Tissue Type

public enum TissueType: String, Codable, Sendable, CaseIterable {
    case closed
    case epithelial
    case granulation
    case slough
    case necroticTissue

    public var subScore: Int {
        switch self {
        case .closed:         return 0
        case .epithelial:     return 1
        case .granulation:    return 2
        case .slough:         return 3
        case .necroticTissue: return 4
        }
    }

    public var displayName: String {
        switch self {
        case .closed:         return "Closed"
        case .epithelial:     return "Epithelial Tissue"
        case .granulation:    return "Granulation Tissue"
        case .slough:         return "Slough"
        case .necroticTissue: return "Necrotic Tissue"
        }
    }
}
