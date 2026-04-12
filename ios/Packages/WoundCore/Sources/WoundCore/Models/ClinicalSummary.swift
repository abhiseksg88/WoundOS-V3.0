import Foundation

// MARK: - Clinical Summary

/// AI-generated clinical narrative summarizing wound status.
/// Produced by Claude Haiku on the backend from measurement data
/// and patient history.
public struct ClinicalSummary: Codable, Sendable, Equatable {

    /// Free-text narrative summary of wound status
    public let narrativeSummary: String

    /// Healing trajectory based on longitudinal data
    public let trajectory: HealingTrajectory

    /// Key clinical findings as bullet points
    public let keyFindings: [String]

    /// Clinical recommendations
    public let recommendations: [String]

    /// When this summary was generated
    public let generatedAt: Date

    /// Model that generated the summary
    public let modelVersion: String

    public init(
        narrativeSummary: String,
        trajectory: HealingTrajectory,
        keyFindings: [String],
        recommendations: [String],
        generatedAt: Date = Date(),
        modelVersion: String
    ) {
        self.narrativeSummary = narrativeSummary
        self.trajectory = trajectory
        self.keyFindings = keyFindings
        self.recommendations = recommendations
        self.generatedAt = generatedAt
        self.modelVersion = modelVersion
    }
}

// MARK: - Healing Trajectory

public enum HealingTrajectory: String, Codable, Sendable {
    case improving
    case stable
    case deteriorating
    case insufficient_data

    public var displayName: String {
        switch self {
        case .improving:         return "Improving"
        case .stable:            return "Stable"
        case .deteriorating:     return "Deteriorating"
        case .insufficient_data: return "Insufficient Data"
        }
    }

    public var symbolName: String {
        switch self {
        case .improving:         return "arrow.down.right"
        case .stable:            return "arrow.right"
        case .deteriorating:     return "arrow.up.right"
        case .insufficient_data: return "questionmark"
        }
    }
}
