import CoreGraphics
import Foundation

// MARK: - Wound Segmenter Protocol

/// Produces a closed boundary polygon around an object in an image,
/// seeded by a single nurse tap point.
///
/// This is the swap-point for segmentation backends: the Apple Vision
/// zero-shot foreground mask (`VisionForegroundSegmenter`, iOS 17+) is the
/// day-1 implementation used for pipeline validation on any object.
/// A wound-fine-tuned SAM 2 / U-Net CoreML model will conform to the same
/// protocol in Phase 2 without touching the drawing scene.
public protocol WoundSegmenter {

    /// Segment the object at `tapPoint` in the given image.
    ///
    /// - Parameters:
    ///   - image: The frozen RGB frame to segment.
    ///   - tapPoint: Nurse tap in image pixel coordinates (origin top-left).
    /// - Returns: A polygon in image pixel coordinates plus quality metadata.
    func segment(
        image: CGImage,
        tapPoint: CGPoint
    ) async throws -> SegmentationResult
}

// MARK: - Segmenter Errors

public enum SegmentationError: Error, LocalizedError {
    case unsupportedOSVersion
    case noForegroundDetected
    case tapPointMissedAllInstances
    case maskGenerationFailed
    case contourExtractionFailed
    case invalidInputImage

    public var errorDescription: String? {
        switch self {
        case .unsupportedOSVersion:
            return "Auto-detect requires iOS 17 or later."
        case .noForegroundDetected:
            return "No object found in the image."
        case .tapPointMissedAllInstances:
            return "Tap was outside every detected object. Try tapping directly on the object."
        case .maskGenerationFailed:
            return "Unable to generate segmentation mask."
        case .contourExtractionFailed:
            return "Unable to trace the object outline."
        case .invalidInputImage:
            return "The captured image is invalid."
        }
    }
}
