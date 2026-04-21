import CoreGraphics
import Foundation
import WoundCore

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Server Segmenter

/// Sends the captured image + tap point to the WoundOS backend's
/// POST /v1/segment endpoint (SAM 2) and converts the response polygon
/// into a `SegmentationResult`.
///
/// This is the primary segmenter for clinical use. Falls back to
/// `VisionForegroundSegmenter` when the server is unreachable.
public final class ServerSegmenter: WoundSegmenter {

    public static let modelIdentifier = "sam2.server.v1"

    /// Closure that performs the actual network call. Injected from the app
    /// layer so this package doesn't need to depend on WoundNetworking.
    /// Parameters: (jpegData, tapPoint, imageWidth, imageHeight)
    /// Returns: (polygon: [[Double]], confidence: Double, modelVersion: String)
    public typealias SegmentRequest = (
        _ jpegData: Data,
        _ tapPoint: (x: Double, y: Double),
        _ imageWidth: Int,
        _ imageHeight: Int
    ) async throws -> (polygon: [[Double]], confidence: Double, modelVersion: String)

    private let segmentRequest: SegmentRequest
    private let fallback: WoundSegmenter?

    public init(segmentRequest: @escaping SegmentRequest, fallback: WoundSegmenter? = nil) {
        self.segmentRequest = segmentRequest
        self.fallback = fallback
    }

    public func segment(
        image: CGImage,
        tapPoint: CGPoint
    ) async throws -> SegmentationResult {
        let imageWidth = image.width
        let imageHeight = image.height

        // Convert CGImage to JPEG data
        guard let jpegData = cgImageToJPEG(image) else {
            if let fallback { return try await fallback.segment(image: image, tapPoint: tapPoint) }
            throw SegmentationError.invalidInputImage
        }

        do {
            // Call backend
            let response = try await segmentRequest(
                jpegData,
                (x: Double(tapPoint.x), y: Double(tapPoint.y)),
                imageWidth,
                imageHeight
            )

            // Convert [[Double]] polygon to [CGPoint]
            let polygon = response.polygon.compactMap { pair -> CGPoint? in
                guard pair.count >= 2 else { return nil }
                return CGPoint(x: pair[0], y: pair[1])
            }

            guard polygon.count >= 3 else {
                if let fallback { return try await fallback.segment(image: image, tapPoint: tapPoint) }
                throw SegmentationError.contourExtractionFailed
            }

            return SegmentationResult(
                polygonImageSpace: polygon,
                imageSize: CGSize(width: imageWidth, height: imageHeight),
                confidence: Float(response.confidence),
                modelIdentifier: response.modelVersion
            )
        } catch {
            // Network failure → fall back to on-device segmentation
            if let fallback { return try await fallback.segment(image: image, tapPoint: tapPoint) }
            throw error
        }
    }

    // MARK: - Helpers

    private func cgImageToJPEG(_ cgImage: CGImage) -> Data? {
        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.85)
        #else
        return nil
        #endif
    }
}
