import Foundation

// MARK: - Capture Quality Score

/// Quality metadata stamped on every measurement at capture time.
/// Lets reviewers and downstream pipelines understand whether a
/// measurement is trustworthy or borderline.
public struct CaptureQualityScore: Codable, Sendable, Equatable {

    /// How long the AR session was in `.normal` tracking before capture (seconds)
    public let trackingStableSeconds: Double

    /// Distance from camera to wound surface at capture time (meters)
    public let captureDistanceM: Double

    /// Number of mesh vertices inside the wound's projected region.
    /// Higher = more spatial detail to compute against.
    public let meshVertexCount: Int

    /// Mean LiDAR confidence (0...2) of depth samples inside the wound region.
    /// 2.0 = all high-confidence, 0.0 = all low-confidence.
    public let meanDepthConfidence: Double

    /// Fraction of boundary points (0...1) that hit the mesh directly via
    /// ray-mesh intersection vs. fell back to depth-map sampling.
    /// 1.0 = perfect, all hit mesh.
    public let meshHitRate: Double

    /// Average angular velocity over the last 0.5s before capture (rad/s).
    /// Lower = more stable hold.
    public let angularVelocityRadPerSec: Double

    /// Computed at this time
    public let computedAt: Date

    public init(
        trackingStableSeconds: Double,
        captureDistanceM: Double,
        meshVertexCount: Int,
        meanDepthConfidence: Double,
        meshHitRate: Double,
        angularVelocityRadPerSec: Double,
        computedAt: Date = Date()
    ) {
        self.trackingStableSeconds = trackingStableSeconds
        self.captureDistanceM = captureDistanceM
        self.meshVertexCount = meshVertexCount
        self.meanDepthConfidence = meanDepthConfidence
        self.meshHitRate = meshHitRate
        self.angularVelocityRadPerSec = angularVelocityRadPerSec
        self.computedAt = computedAt
    }

    // MARK: - Quality Tier

    /// Overall quality tier derived from individual signals.
    public var tier: QualityTier {
        let inDistance = (0.15...0.30).contains(captureDistanceM)
        let highConfidence = meanDepthConfidence >= 1.7
        let highHitRate = meshHitRate >= 0.95
        let denseMesh = meshVertexCount >= 500
        let stable = trackingStableSeconds >= 1.5 && angularVelocityRadPerSec < 0.05

        let passing = [inDistance, highConfidence, highHitRate, denseMesh, stable].filter { $0 }.count

        switch passing {
        case 5: return .excellent
        case 4: return .good
        case 3: return .fair
        default: return .poor
        }
    }
}

// MARK: - Quality Tier

public enum QualityTier: String, Codable, Sendable {
    case excellent
    case good
    case fair
    case poor

    public var displayName: String {
        rawValue.capitalized
    }
}
