import Foundation

// MARK: - Wound Type

/// Clinical wound type used for segmenter routing.
/// `footUlcer` routes to on-device CoreML segmenter when available;
/// all other types route to the server (SAM 2).
public enum WoundType: String, Codable, Sendable, CaseIterable {
    case footUlcer = "foot_ulcer"
    case pressureInjury = "pressure_injury"
    case surgicalWound = "surgical_wound"
    case venousLegUlcer = "venous_leg_ulcer"
    case unknown = "unknown"
}
