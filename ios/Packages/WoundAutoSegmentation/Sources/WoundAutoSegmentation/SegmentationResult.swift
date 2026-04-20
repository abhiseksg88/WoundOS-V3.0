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
    /// Example values: `"apple.vision.foreground.v1"`, `"sam2.coreml.v2.1"`.
    public let modelIdentifier: String

    public init(
        polygonImageSpace: [CGPoint],
        imageSize: CGSize,
        confidence: Float,
        modelIdentifier: String
    ) {
        self.polygonImageSpace = polygonImageSpace
        self.imageSize = imageSize
        self.confidence = confidence
        self.modelIdentifier = modelIdentifier
    }
}
