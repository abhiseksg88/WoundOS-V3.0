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

        // 2. Pick the instance under the tap (or largest if tap missed)
        let targetInstances = pickInstances(
            observation: observation,
            tapPoint: tapPoint,
            imageSize: imageSize
        )
        guard !targetInstances.isEmpty else {
            throw SegmentationError.tapPointMissedAllInstances
        }

        // 3. Generate binary mask for that instance
        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: targetInstances,
                from: handler
            )
        } catch {
            throw SegmentationError.maskGenerationFailed
        }

        // 4. Extract contours from the mask
        let contour = try extractLargestContour(
            maskBuffer: maskBuffer,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        // 5. Simplify
        let simplified = ContourSimplifier.simplify(contour)

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

    // MARK: - Instance Selection

    /// Walk each detected instance's mask and return the one whose mask is
    /// non-zero at the tap. Fall back to the largest instance if the tap
    /// missed everything (common when the user taps near — but not on — the
    /// object).
    private func pickInstances(
        observation: VNInstanceMaskObservation,
        tapPoint: CGPoint,
        imageSize: CGSize
    ) -> IndexSet {
        let instances = observation.allInstances
        if instances.isEmpty {
            return IndexSet()
        }

        // Sample the instance mask directly. Apple exposes the raw multi-
        // class mask as a CVPixelBuffer with values 0=bg, 1..N=instance idx.
        let buffer = observation.instanceMask
        if let hitIndex = MaskSampler.instanceIndexAt(
            buffer: buffer,
            normalizedX: tapPoint.x / imageSize.width,
            normalizedY: tapPoint.y / imageSize.height
        ), hitIndex > 0 {
            return IndexSet(integer: Int(hitIndex))
        }

        // Fallback: pick the largest instance by mask area.
        var bestIdx: Int?
        var bestArea = 0
        for idx in instances {
            let area = MaskSampler.area(buffer: buffer, instanceIndex: UInt8(idx))
            if area > bestArea {
                bestArea = area
                bestIdx = idx
            }
        }
        if let bestIdx {
            return IndexSet(integer: bestIdx)
        }
        return IndexSet()
    }

    // MARK: - Contour Extraction

    private func extractLargestContour(
        maskBuffer: CVPixelBuffer,
        imageSize: CGSize,
        tapPoint: CGPoint
    ) throws -> [CGPoint] {
        let contoursRequest = VNDetectContoursRequest()
        contoursRequest.contrastAdjustment = 1.0
        contoursRequest.detectsDarkOnLight = false
        contoursRequest.maximumImageDimension = 512

        let handler = VNImageRequestHandler(cvPixelBuffer: maskBuffer, orientation: .up)
        do {
            try handler.perform([contoursRequest])
        } catch {
            throw SegmentationError.contourExtractionFailed
        }

        guard let obs = contoursRequest.results?.first else {
            throw SegmentationError.contourExtractionFailed
        }

        // Flatten to a list of top-level contours. If multiple disconnected
        // blobs exist, prefer the one containing the tap; otherwise the
        // largest by bounding box area.
        let topLevel = (0..<obs.topLevelContourCount).compactMap { i in
            try? obs.topLevelContour(at: i)
        }
        guard !topLevel.isEmpty else {
            throw SegmentationError.contourExtractionFailed
        }

        let tapNormalizedVision = CGPoint(
            x: tapPoint.x / imageSize.width,
            y: 1.0 - (tapPoint.y / imageSize.height) // Vision origin is bottom-left
        )

        let chosen = chooseBestContour(topLevel, tapNormalized: tapNormalizedVision)

        // Convert Vision's normalized bottom-left coords → image pixel top-left
        let pts = chosen.normalizedPoints.map { p -> CGPoint in
            CGPoint(
                x: CGFloat(p.x) * imageSize.width,
                y: (1.0 - CGFloat(p.y)) * imageSize.height
            )
        }
        return pts
    }

    private func chooseBestContour(
        _ contours: [VNContour],
        tapNormalized: CGPoint
    ) -> VNContour {
        // 1. Prefer the contour whose bounding box contains the tap.
        for c in contours {
            if c.normalizedPath.boundingBox.contains(tapNormalized) {
                return c
            }
        }
        // 2. Fall back to the largest by bounding box area.
        return contours.max(by: { lhs, rhs in
            let la = lhs.normalizedPath.boundingBox
            let ra = rhs.normalizedPath.boundingBox
            return (la.width * la.height) < (ra.width * ra.height)
        })!
    }
}
