import CoreGraphics
import CoreImage
import Foundation
import Vision

#if canImport(UIKit)
import UIKit
#endif

// DEPRECATED for V5 production path.
// Retained for reference and for unit tests only.
// Caused false-positive segmentation on non-wounds (hairbrush, credit card,
// bowl) during Phase 2 adversarial testing — produced measurements like
// 1932 cm² on non-wound objects. Do not reinstate without wound-specific
// gate in front.
//
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

        // 2. Try individual instances — find the one whose mask contains the tap point.
        //    This avoids merging all foreground (arm + laptop + pillow) into one giant blob.
        let instances = observation.allInstances
        guard !instances.isEmpty else {
            throw SegmentationError.noForegroundDetected
        }

        // 3. Generate per-instance masks and pick the one under the tap point
        let maskBuffer: CVPixelBuffer
        do {
            var bestMask: CVPixelBuffer?

            // Check each instance individually
            for instance in instances {
                let individualMask = try observation.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instance),
                    from: handler
                )
                if Self.maskContainsTapPoint(individualMask, tapPoint: tapPoint, imageSize: imageSize) {
                    bestMask = individualMask
                    break
                }
            }

            // Fallback: if no individual instance contains the tap,
            // use the smallest instance (most likely a wound, not the whole arm)
            if bestMask == nil {
                var smallestArea = Int.max
                for instance in instances {
                    let individualMask = try observation.generateScaledMaskForImage(
                        forInstances: IndexSet(integer: instance),
                        from: handler
                    )
                    let area = Self.maskPixelCount(individualMask)
                    if area < smallestArea && area > 0 {
                        smallestArea = area
                        bestMask = individualMask
                    }
                }
            }

            if let best = bestMask {
                maskBuffer = best
            } else {
                maskBuffer = try observation.generateScaledMaskForImage(
                    forInstances: instances,
                    from: handler
                )
            }
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

    // MARK: - Mask Helpers

    /// Check if the mask pixel at the tap point location is active (> 0.5).
    private static func maskContainsTapPoint(
        _ mask: CVPixelBuffer,
        tapPoint: CGPoint,
        imageSize: CGSize
    ) -> Bool {
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        guard maskWidth > 0, maskHeight > 0,
              imageSize.width > 0, imageSize.height > 0 else { return false }

        // Map image-space tap to mask pixel coords
        let mx = Int(tapPoint.x / imageSize.width * CGFloat(maskWidth))
        let my = Int(tapPoint.y / imageSize.height * CGFloat(maskHeight))
        guard mx >= 0, mx < maskWidth, my >= 0, my < maskHeight else { return false }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(mask) else { return false }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)

        // OneComponent8 format — each pixel is a UInt8 (0-255)
        let pixelFormat = CVPixelBufferGetPixelFormatType(mask)
        if pixelFormat == kCVPixelFormatType_OneComponent8 {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let value = ptr[my * bytesPerRow + mx]
            return value > 128
        }

        // OneComponent32Float format
        if pixelFormat == kCVPixelFormatType_OneComponent32Float {
            let ptr = base.assumingMemoryBound(to: Float.self)
            let floatsPerRow = bytesPerRow / MemoryLayout<Float>.size
            let value = ptr[my * floatsPerRow + mx]
            return value > 0.5
        }

        return false
    }

    /// Count non-zero pixels in the mask (approximation of instance area).
    private static func maskPixelCount(_ mask: CVPixelBuffer) -> Int {
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        var count = 0

        let pixelFormat = CVPixelBufferGetPixelFormatType(mask)
        if pixelFormat == kCVPixelFormatType_OneComponent8 {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    if ptr[y * bytesPerRow + x] > 128 { count += 1 }
                }
            }
        } else if pixelFormat == kCVPixelFormatType_OneComponent32Float {
            let ptr = base.assumingMemoryBound(to: Float.self)
            let floatsPerRow = bytesPerRow / MemoryLayout<Float>.size
            for y in 0..<height {
                for x in 0..<width {
                    if ptr[y * floatsPerRow + x] > 0.5 { count += 1 }
                }
            }
        }

        return count
    }
}
