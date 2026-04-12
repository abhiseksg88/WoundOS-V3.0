import Foundation

// MARK: - Wound Measurement

/// All clinical measurements derived from a wound boundary projected
/// onto the frozen ARKit mesh. Computed entirely on-device.
public struct WoundMeasurement: Codable, Sendable, Equatable {

    /// Surface area of the wound in cm²
    /// Computed by summing clipped mesh triangle areas.
    public let areaCm2: Double

    /// Maximum depth from the wound rim reference plane in mm
    public let maxDepthMm: Double

    /// Mean depth from the wound rim reference plane in mm
    public let meanDepthMm: Double

    /// Volume below the reference plane in mL (cm³)
    public let volumeMl: Double

    /// Greatest linear dimension across the wound in mm
    /// (head-to-toe axis or longest caliper distance)
    public let lengthMm: Double

    /// Greatest dimension perpendicular to length in mm
    public let widthMm: Double

    /// Perimeter of the wound boundary on the mesh surface in mm
    public let perimeterMm: Double

    /// Who/what produced this measurement
    public let source: MeasurementSource

    /// Whether this was computed on-device or on the backend
    public let computedOnDevice: Bool

    /// Time taken to compute these measurements in milliseconds
    public let processingTimeMs: Int

    /// Timestamp of computation
    public let computedAt: Date

    public init(
        areaCm2: Double,
        maxDepthMm: Double,
        meanDepthMm: Double,
        volumeMl: Double,
        lengthMm: Double,
        widthMm: Double,
        perimeterMm: Double,
        source: MeasurementSource,
        computedOnDevice: Bool,
        processingTimeMs: Int,
        computedAt: Date = Date()
    ) {
        self.areaCm2 = areaCm2
        self.maxDepthMm = maxDepthMm
        self.meanDepthMm = meanDepthMm
        self.volumeMl = volumeMl
        self.lengthMm = lengthMm
        self.widthMm = widthMm
        self.perimeterMm = perimeterMm
        self.source = source
        self.computedOnDevice = computedOnDevice
        self.processingTimeMs = processingTimeMs
        self.computedAt = computedAt
    }
}

// MARK: - Measurement Source

public enum MeasurementSource: String, Codable, Sendable {
    /// Computed from nurse-drawn boundary + ARKit mesh (primary path)
    case nurseBoundary = "nurse_drawn"
    /// Computed from SAM 2 boundary + same ARKit mesh (shadow path)
    case sam2Boundary = "sam2"
    /// Recomputed after clinician review correction
    case clinicianReview = "clinician_review"
}
