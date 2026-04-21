import CoreGraphics
import CoreImage
import Foundation
import Vision

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Vision Foreground Segmenter (iOS 17+)

/// Day-1 zero-shot segmenter backed by Apple's `VNGenerateForegroundInstanceMaskRequest`.
///
/// Pipeline:
///  1. Run `VNGenerateForegroundInstanceMaskRequest` on the frozen RGB image.
///  2. Sample the observation's instance mask at the nurse tap point to pick
///     the instance under the tap (falls back to the largest instance).
///  3. Generate a scaled binary mask for that single instance.
///  4. Run `VNDetectContoursRequest` on the mask to extract its outline.
///  5. Pick the longest/largest top-level contour, convert normalized
///     bottom-left Vision coords to image-space pixel top-left coords.
///  6. Hand to `ContourSimplifier` → closed polygon with ~30–80 vertices.
///
/// This runs entirely on-device via the Neural Engine. Typical A17 latency
/// is 120–250 ms for a 1080 × 1080 input.
///
/// Swappable: anything conforming to `WoundSegmenter` plugs in behind it
/// without touching the drawing scene. Phase 2 replaces this with a
/// wound-fine-tuned SAM 2 / U-Net CoreML model.
@available(iOS 17.0, *)
public final class VisionForegroundSegmenter: WoundSegmenter {

    public static let modelIdentifier = "apple.vision.foreground.v1"

    public init() {}

    public func segment(
        image: CGImage,
        tapPoint: CGPoint
    ) async throws -> SegmentationResult {
        let imageSize = CGSize(width: image.width, height: image.height)
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)

        // 1. Foreground instance segmentation
        let fgRequest = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([fgRequest])
        } catch {
            throw SegmentationError.maskGenerationFailed
        }

        guard let observation = fgRequest.results?.first else {
            throw SegmentationError.noForegroundDetected
        }

        // 2. Use all detected instances — contour selection will pick the
        //    blob nearest the tap. This avoids accessing the non-public
        //    `instanceMask` property that crashes on iOS 17 (Bug 2 fix).
        let instances = observation.allInstances
        guard !instances.isEmpty else {
            throw SegmentationError.noForegroundDetected
        }

        // 3. Generate combined binary mask for all foreground instances
        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: instances,
                from: handler
            )
        } catch {
            throw SegmentationError.maskGenerationFailed
        }

        // 4. Extract contours from the mask (shared with WoundAmbitSegmenter).
        //    MaskContourExtractor.chooseBestContour picks the contour nearest
        //    the tap point, so per-instance selection is unnecessary.
        let contour = try MaskContourExtractor.extractContour(
            from: maskBuffer,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        // 5. Simplify
        let simplified = ContourSimplifier.simplify(contour)

        guard simplified.count >= 3 else {
            throw SegmentationError.contourExtractionFailed
        }

        // Confidence: Apple Vision's foreground request doesn't expose a
        // numeric confidence. We proxy it with the observation's overall
        // confidence field. A real wound model will return mean-pixel prob.
        let confidence = observation.confidence

        return SegmentationResult(
            polygonImageSpace: simplified,
            imageSize: imageSize,
            confidence: confidence,
            modelIdentifier: Self.modelIdentifier
        )
    }

}
