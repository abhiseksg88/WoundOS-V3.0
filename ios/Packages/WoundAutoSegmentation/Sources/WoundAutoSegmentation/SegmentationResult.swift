import CoreGraphics
import Foundation

// MARK: - Segmentation Result

/// Output of a `WoundSegmenter`.
///
/// Points are in the **source image's pixel coordinate space** (origin
/// top-left). The drawing scene is responsible for converting to its
/// view-local space, then the existing normalization / projection
/// pipeline takes over — identical to the nurse-drawn flow.
public struct SegmentationResult {

    /// Closed polygon around the detected object, in image pixel coordinates.
    /// Ordered; last → first edge implied (the pipeline already assumes this).
    public let polygonImageSpace: [CGPoint]

    /// The size of the image the polygon was computed against.
    public let imageSize: CGSize

    /// Model confidence in the mask (0...1). For Apple Vision this is derived
    /// from the observation's global confidence. For a trained U-Net this will
    /// be the mean per-pixel probability over the boundary.
    public let confidence: Float

    /// Identifier for the backend that produced this result. Stored with the
    /// scan so audit trails show which segmenter drew the initial boundary.
    /// Example values: `"apple.vision.foreground.v1"`, `"sam2.server.v1"`.
    public let modelIdentifier: String

    /// Number of connected foreground regions detected in the mask.
    /// 1 = clean single-region mask. >1 = disjoint blobs.
    /// Defaults to 1 for backwards compatibility with segmenters that
    /// don't report component count.
    public let connectedComponents: Int

    /// Quality gate evaluation result. `.accept` if the mask passed all
    /// checks, `.reject(reason:detail:)` if it failed.
    public let qualityResult: MaskQualityResult

    /// Time taken for the segmentation inference in milliseconds.
    public let inferenceLatencyMs: Double

    public init(
        polygonImageSpace: [CGPoint],
        imageSize: CGSize,
        confidence: Float,
        modelIdentifier: String,
        connectedComponents: Int = 1,
        qualityResult: MaskQualityResult = .accept,
        inferenceLatencyMs: Double = 0
    ) {
        self.polygonImageSpace = polygonImageSpace
        self.imageSize = imageSize
        self.confidence = confidence
        self.modelIdentifier = modelIdentifier
        self.connectedComponents = connectedComponents
        self.qualityResult = qualityResult
        self.inferenceLatencyMs = inferenceLatencyMs
    }

    /// Whether this result passed the quality gate and is usable for measurement.
    public var isUsable: Bool {
        qualityResult.isAccepted
    }

    /// Convenience factory for creating a rejected result when segmentation
    /// fails before producing a polygon (e.g., network timeout).
    public static func rejected(
        reason: MaskRejectionReason,
        detail: String,
        modelIdentifier: String,
        imageSize: CGSize
    ) -> SegmentationResult {
        SegmentationResult(
            polygonImageSpace: [],
            imageSize: imageSize,
            confidence: 0,
            modelIdentifier: modelIdentifier,
            connectedComponents: 0,
            qualityResult: .reject(reason: reason, detail: detail),
            inferenceLatencyMs: 0
        )
    }
}
