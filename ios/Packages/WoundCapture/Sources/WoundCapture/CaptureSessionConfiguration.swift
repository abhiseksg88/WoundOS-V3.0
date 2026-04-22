import Foundation

/// Configuration for the AR capture session.
public struct CaptureSessionConfiguration {

    /// Optimal distance range from camera to wound surface (meters)
    public let optimalDistanceRange: ClosedRange<Float>

    /// Whether to enable mesh classification (ground, wall, etc.)
    public let enableMeshClassification: Bool

    /// Target image resolution for capture
    public let preferredImageResolution: ImageResolution

    /// Minimum tracking confidence to allow capture
    public let minimumTrackingConfidence: Float

    public static let `default` = CaptureSessionConfiguration(
        optimalDistanceRange: 0.15...0.30,
        enableMeshClassification: false,
        preferredImageResolution: .high,
        minimumTrackingConfidence: 0.8
    )

    /// V5 configuration with tighter optimal distance range (20-35 cm)
    public static let v5Default = CaptureSessionConfiguration(
        optimalDistanceRange: 0.20...0.35,
        enableMeshClassification: false,
        preferredImageResolution: .high,
        minimumTrackingConfidence: 0.8
    )

    public init(
        optimalDistanceRange: ClosedRange<Float>,
        enableMeshClassification: Bool,
        preferredImageResolution: ImageResolution,
        minimumTrackingConfidence: Float
    ) {
        self.optimalDistanceRange = optimalDistanceRange
        self.enableMeshClassification = enableMeshClassification
        self.preferredImageResolution = preferredImageResolution
        self.minimumTrackingConfidence = minimumTrackingConfidence
    }
}

public enum ImageResolution: Sendable {
    case high    // 3840×2160 or best available
    case medium  // 1920×1080
}
