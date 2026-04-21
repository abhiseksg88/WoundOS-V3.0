import CoreGraphics
import CoreVideo
import Foundation
import Vision

// MARK: - Mask Contour Extractor

/// Shared utility that converts a binary mask `CVPixelBuffer` into a polygon
/// of image-space pixel coordinates using Apple Vision's contour detection.
///
/// Used by both `VisionForegroundSegmenter` (Apple's generic foreground mask)
/// and `WoundAmbitSegmenter` (CoreML wound-specific model). Extracting this
/// into a shared enum eliminates ~70 lines of duplicated contour logic.
public enum MaskContourExtractor {

    /// Extract the largest contour from a binary mask and return it as a
    /// polygon in image-space pixel coordinates (origin top-left).
    ///
    /// - Parameters:
    ///   - maskBuffer: Single-channel binary mask (foreground > 0).
    ///   - imageSize: The original image size the polygon should map to.
    ///   - tapPoint: Nurse tap in image pixel coordinates — used to prefer
    ///     the contour nearest the tap when multiple disconnected blobs exist.
    /// - Returns: Array of `CGPoint` forming a closed polygon.
    public static func extractContour(
        from maskBuffer: CVPixelBuffer,
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

        let topLevel = obs.topLevelContours
        guard !topLevel.isEmpty else {
            throw SegmentationError.contourExtractionFailed
        }

        // Vision uses bottom-left origin; convert tap to that space.
        let tapNormalizedVision = CGPoint(
            x: tapPoint.x / imageSize.width,
            y: 1.0 - (tapPoint.y / imageSize.height)
        )

        guard let chosen = chooseBestContour(topLevel, tapNormalized: tapNormalizedVision) else {
            throw SegmentationError.contourExtractionFailed
        }

        // Convert Vision's normalized bottom-left coords → image pixel top-left
        let pts = chosen.normalizedPoints.map { p -> CGPoint in
            CGPoint(
                x: CGFloat(p.x) * imageSize.width,
                y: (1.0 - CGFloat(p.y)) * imageSize.height
            )
        }
        return pts
    }

    // MARK: - Contour Selection

    /// Pick the best contour from a set of top-level contours.
    /// Prefers the contour whose bounding box contains the tap point;
    /// falls back to the largest by bounding box area.
    private static func chooseBestContour(
        _ contours: [VNContour],
        tapNormalized: CGPoint
    ) -> VNContour? {
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
        })
    }
}
