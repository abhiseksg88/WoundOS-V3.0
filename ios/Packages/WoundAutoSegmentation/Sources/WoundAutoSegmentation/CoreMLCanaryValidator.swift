import CoreGraphics
import CoreVideo
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Canary Validation Result

/// Result of running the canary (deployment health check) on the CoreML model.
public struct CanaryResult: Sendable {
    /// Intersection over Union between predicted and reference mask.
    public let iou: Float
    /// Whether the IoU meets the threshold (≥ 0.95).
    public let passed: Bool
    /// Expected positive pixels in the reference mask.
    public let expectedPositivePixels: Int
    /// Actual positive pixels in the model's prediction.
    public let actualPositivePixels: Int
    /// Time taken for the canary inference in milliseconds.
    public let latencyMs: Double

    public init(
        iou: Float,
        passed: Bool,
        expectedPositivePixels: Int,
        actualPositivePixels: Int,
        latencyMs: Double
    ) {
        self.iou = iou
        self.passed = passed
        self.expectedPositivePixels = expectedPositivePixels
        self.actualPositivePixels = actualPositivePixels
        self.latencyMs = latencyMs
    }
}

// MARK: - CoreML Canary Validator

/// Deployment health check for the CoreML boundary segmentation model.
///
/// Runs a known reference image through the model and compares the output
/// mask to a stored reference mask using pixel-level IoU. If IoU < 0.95,
/// the model is considered corrupt or incompatible and the `ChainedSegmenter`
/// permanently degrades to server fallback.
///
/// The canary runs lazily on the first `ChainedSegmenter.segment()` call,
/// not at app launch, to avoid blocking startup.
public final class CoreMLCanaryValidator {

    /// Minimum IoU between predicted and reference mask for the canary to pass.
    public static let iouThreshold: Float = 0.95

    /// Expected positive pixels in the reference mask (512×512).
    public static let expectedPositivePixels = 13_132

    /// Mask dimensions (matches model input/output size).
    public static let maskSize = 512

    private let segmenter: CoreMLBoundarySegmenter

    public init(segmenter: CoreMLBoundarySegmenter) {
        self.segmenter = segmenter
    }

    /// Run canary validation. Returns the result.
    /// Caller (`ChainedSegmenter`) decides behavior on failure.
    public func validate() async throws -> CanaryResult {
        // 1. Load reference image from bundle
        guard let refImage = loadReferenceImage() else {
            throw SegmentationError.modelLoadFailed
        }

        // 2. Load reference mask from bundle
        guard let refMask = loadReferenceMask() else {
            throw SegmentationError.modelLoadFailed
        }

        // 3. Run model on reference image
        let startTime = CFAbsoluteTimeGetCurrent()
        let predictedMask = try await segmenter.segmentToMask(image: refImage)
        let latencyMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // 4. Read predicted mask into flat UInt8 array
        let predictedFlat = readMaskPixels(predictedMask)
        let actualPositive = predictedFlat.filter { $0 > 0 }.count

        // 5. Compute IoU
        let iou = Self.computeIoU(predicted: predictedFlat, reference: refMask)

        return CanaryResult(
            iou: iou,
            passed: iou >= Self.iouThreshold,
            expectedPositivePixels: Self.expectedPositivePixels,
            actualPositivePixels: actualPositive,
            latencyMs: latencyMs
        )
    }

    // MARK: - IoU Computation

    /// Compute pixel-level Intersection over Union between two binary masks.
    /// Both arrays must have the same length (maskSize × maskSize).
    /// Pixels > 0 are treated as foreground.
    public static func computeIoU(predicted: [UInt8], reference: [UInt8]) -> Float {
        guard predicted.count == reference.count, !predicted.isEmpty else { return 0 }

        var intersection = 0
        var union = 0

        for i in 0..<predicted.count {
            let p = predicted[i] > 0
            let r = reference[i] > 0
            if p && r { intersection += 1 }
            if p || r { union += 1 }
        }

        return union > 0 ? Float(intersection) / Float(union) : 0
    }

    // MARK: - Reference Artifact Loading

    /// Load the 512×512 reference input image from the bundle.
    private func loadReferenceImage() -> CGImage? {
        let bundles = [Bundle(for: CoreMLCanaryValidator.self), Bundle.main]

        for bundle in bundles {
            if let url = bundle.url(
                forResource: "boundaryseg_v1_reference",
                withExtension: "png",
                subdirectory: "CanaryReferences"
            ) {
                #if canImport(UIKit)
                if let image = UIImage(contentsOfFile: url.path)?.cgImage {
                    return image
                }
                #else
                if let dataProvider = CGDataProvider(url: url as CFURL),
                   let image = CGImage(
                       pngDataProviderSource: dataProvider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent
                   ) {
                    return image
                }
                #endif
            }
        }
        return nil
    }

    /// Load the reference binary mask from the bundle.
    /// Expected format: flat 512×512 UInt8 array (0 = background, 255 = foreground).
    private func loadReferenceMask() -> [UInt8]? {
        let bundles = [Bundle(for: CoreMLCanaryValidator.self), Bundle.main]

        let expectedSize = Self.maskSize * Self.maskSize

        for bundle in bundles {
            if let url = bundle.url(
                forResource: "boundaryseg_v1_reference_mask",
                withExtension: "bin",
                subdirectory: "CanaryReferences"
            ) {
                if let data = try? Data(contentsOf: url), data.count == expectedSize {
                    return [UInt8](data)
                }
            }
        }
        return nil
    }

    // MARK: - Mask Reading

    /// Read a OneComponent8 CVPixelBuffer into a flat UInt8 array.
    private func readMaskPixels(_ buffer: CVPixelBuffer) -> [UInt8] {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var result = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                result[y * width + x] = ptr[y * stride + x]
            }
        }
        return result
    }
}
