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
/// This is the primary segmenter for clinical use. When the server is
/// unreachable, returns a rejected SegmentationResult with a specific
/// reason — no silent fallback to VisionForegroundSegmenter.
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
    private let qualityThresholds: MaskQualityThresholds

    public init(
        segmentRequest: @escaping SegmentRequest,
        qualityThresholds: MaskQualityThresholds = .default
    ) {
        self.segmentRequest = segmentRequest
        self.qualityThresholds = qualityThresholds
    }

    public func segment(
        image: CGImage,
        tapPoint: CGPoint
    ) async throws -> SegmentationResult {
        let imageWidth = image.width
        let imageHeight = image.height
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        let startTime = CFAbsoluteTimeGetCurrent()

        // Convert CGImage to JPEG data
        guard let jpegData = cgImageToJPEG(image) else {
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

            let latencyMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            // Convert [[Double]] polygon to [CGPoint]
            let polygon = response.polygon.compactMap { pair -> CGPoint? in
                guard pair.count >= 2 else { return nil }
                return CGPoint(x: pair[0], y: pair[1])
            }

            guard polygon.count >= 3 else {
                throw SegmentationError.contourExtractionFailed
            }

            // Run quality gate on the result.
            // Connected components = 1 for server results (SAM 2 returns
            // a single mask per tap point).
            let qualityResult = MaskQualityGate.evaluate(
                polygon: polygon,
                imageSize: imageSize,
                confidence: Float(response.confidence),
                connectedComponents: 1,
                thresholds: qualityThresholds
            )

            return SegmentationResult(
                polygonImageSpace: polygon,
                imageSize: imageSize,
                confidence: Float(response.confidence),
                modelIdentifier: response.modelVersion,
                connectedComponents: 1,
                qualityResult: qualityResult,
                inferenceLatencyMs: latencyMs
            )
        } catch let segError as SegmentationError {
            throw segError
        } catch {
            // Network failure — no silent fallback. Return a rejected result
            // so the UI can show a specific message.
            throw SegmentationError.serviceUnavailable(underlying: error)
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
