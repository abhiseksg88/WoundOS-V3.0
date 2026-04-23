import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

#if canImport(UIKit)
import UIKit
#endif

// MARK: - CoreML Boundary Segmenter

/// On-device wound boundary segmenter backed by the BoundarySeg CoreML model
/// (foot ulcer semantic segmentation).
///
/// Pipeline:
///  1. Load `BoundarySeg.mlpackage` from the SPM bundle at init.
///  2. Resize input `CGImage` to 512×512.
///  3. Run CoreML prediction → single-channel FLOAT16 logits.
///  4. Apply sigmoid, threshold at 0.5 → binary mask.
///  5. Extract contour via shared `MaskContourExtractor`.
///  6. Simplify with `ContourSimplifier`.
///  7. Run `MaskQualityGate.evaluate()`.
///  8. Return `SegmentationResult`.
///
/// This is a whole-image semantic segmenter — the `tapPoint` parameter
/// from `WoundSegmenter` is accepted but **ignored**. The model segments
/// the entire visible wound without a point prompt.
///
/// ImageNet normalization is baked into the model — no Swift-side
/// preprocessing beyond resize is needed.
public final class CoreMLBoundarySegmenter: WoundSegmenter {

    public static let modelIdentifier = "boundaryseg.coreml.v1"

    /// Model input resolution (width and height).
    private static let inputSize = 512

    /// Sigmoid threshold for binary mask generation.
    private static let maskThreshold: Float = 0.5

    private let model: MLModel
    private let qualityThresholds: MaskQualityThresholds

    /// Initialize by loading the BoundarySeg CoreML model from the bundle.
    /// Throws `SegmentationError.modelLoadFailed` if the model is missing or corrupt.
    public init(qualityThresholds: MaskQualityThresholds = .default) throws {
        guard let modelURL = Self.findModelURL() else {
            throw SegmentationError.modelLoadFailed
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Use Neural Engine when available
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
            self.qualityThresholds = qualityThresholds
        } catch {
            throw SegmentationError.modelLoadFailed
        }
    }

    /// Search for the BoundarySeg model across known bundle locations.
    /// Checks the class bundle (SPM package bundle) and main app bundle.
    private static func findModelURL() -> URL? {
        let extensions = ["mlmodelc", "mlpackage"]
        #if SWIFT_PACKAGE
        let bundles = [Bundle.module, Bundle(for: CoreMLBoundarySegmenter.self), Bundle.main]
        #else
        let bundles = [Bundle(for: CoreMLBoundarySegmenter.self), Bundle.main]
        #endif

        for bundle in bundles {
            for ext in extensions {
                if let url = bundle.url(forResource: "BoundarySeg", withExtension: ext) {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - WoundSegmenter Conformance

    public func segment(
        image: CGImage,
        tapPoint: CGPoint // ignored — whole-image semantic segmenter
    ) async throws -> SegmentationResult {
        let imageSize = CGSize(width: image.width, height: image.height)
        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Run single inference pass → get logits, mask, and confidence
        let inferenceOutput = try await runInference(image: image)

        let latencyMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // 2. Extract contour with connected component count
        let contourResult = try MaskContourExtractor.extractContourWithComponents(
            from: inferenceOutput.maskBuffer,
            imageSize: imageSize,
            tapPoint: tapPoint // used for contour selection, not segmentation
        )

        // 3. Simplify
        let simplified = ContourSimplifier.simplify(contourResult.polygon)

        guard simplified.count >= 3 else {
            throw SegmentationError.contourExtractionFailed
        }

        // 4. Run quality gate
        let qualityResult = MaskQualityGate.evaluate(
            polygon: simplified,
            imageSize: imageSize,
            confidence: inferenceOutput.confidence,
            connectedComponents: contourResult.connectedComponentCount,
            thresholds: qualityThresholds
        )

        return SegmentationResult(
            polygonImageSpace: simplified,
            imageSize: imageSize,
            confidence: inferenceOutput.confidence,
            modelIdentifier: Self.modelIdentifier,
            connectedComponents: contourResult.connectedComponentCount,
            qualityResult: qualityResult,
            inferenceLatencyMs: latencyMs
        )
    }

    // MARK: - Internal (Canary Validator Access)

    /// Single-pass inference result containing both mask and confidence.
    struct InferenceOutput {
        let maskBuffer: CVPixelBuffer
        let confidence: Float
    }

    /// Run model inference and return the binary mask CVPixelBuffer.
    /// Used by `CoreMLCanaryValidator` for IoU comparison.
    func segmentToMask(image: CGImage) async throws -> CVPixelBuffer {
        try await runInference(image: image).maskBuffer
    }

    /// Single inference pass that produces both the binary mask and confidence.
    /// Avoids running the model twice.
    private func runInference(image: CGImage) async throws -> InferenceOutput {
        // 1. Resize to model input size
        guard let resizedBuffer = resizeToPixelBuffer(
            image,
            width: Self.inputSize,
            height: Self.inputSize
        ) else {
            throw SegmentationError.invalidInputImage
        }

        // 2. Run CoreML prediction
        let prediction: MLFeatureProvider
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: resizedBuffer)
            ])
            prediction = try await model.prediction(from: input)
        } catch {
            throw SegmentationError.predictionFailed
        }

        // 3. Extract output logits
        guard let outputArray = prediction.featureValue(
            for: "mask_logit"
        )?.multiArrayValue ?? firstMultiArrayOutput(prediction) else {
            throw SegmentationError.predictionFailed
        }

        // 4. Apply sigmoid + threshold to binary mask AND compute confidence in one pass
        let (maskBuffer, confidence) = try sigmoidThresholdToMaskAndConfidence(
            outputArray,
            width: Self.inputSize,
            height: Self.inputSize
        )

        return InferenceOutput(maskBuffer: maskBuffer, confidence: confidence)
    }

    // MARK: - Sigmoid + Threshold (FLOAT16 / Float32)

    /// Apply sigmoid to raw logits, threshold to binary mask, and compute
    /// mean foreground confidence — all in a single pass.
    /// Handles both FLOAT16 and Float32 MLMultiArray output types.
    private func sigmoidThresholdToMaskAndConfidence(
        _ multiArray: MLMultiArray,
        width: Int,
        height: Int
    ) throws -> (CVPixelBuffer, Float) {
        var maskBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &maskBuffer
        )
        guard status == kCVReturnSuccess, let buffer = maskBuffer else {
            throw SegmentationError.maskGenerationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw SegmentationError.maskGenerationFailed
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let totalPixels = width * height

        var confidenceSum: Float = 0
        var foregroundCount: Int = 0

        switch multiArray.dataType {
        case .float16:
            let dataPtr = multiArray.dataPointer.assumingMemoryBound(to: Float16.self)
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * width + x
                    guard idx < totalPixels else { continue }
                    let logit = Float(dataPtr[idx])
                    let sigmoid = 1.0 / (1.0 + exp(-logit))
                    if sigmoid >= Self.maskThreshold {
                        ptr[y * stride + x] = 255
                        confidenceSum += sigmoid
                        foregroundCount += 1
                    } else {
                        ptr[y * stride + x] = 0
                    }
                }
            }
        case .float32:
            let dataPtr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * width + x
                    guard idx < totalPixels else { continue }
                    let logit = dataPtr[idx]
                    let sigmoid = 1.0 / (1.0 + exp(-logit))
                    if sigmoid >= Self.maskThreshold {
                        ptr[y * stride + x] = 255
                        confidenceSum += sigmoid
                        foregroundCount += 1
                    } else {
                        ptr[y * stride + x] = 0
                    }
                }
            }
        default:
            throw SegmentationError.predictionFailed
        }

        let confidence = foregroundCount > 0 ? confidenceSum / Float(foregroundCount) : 0

        return (buffer, confidence)
    }

    // MARK: - Image Preprocessing

    /// Resize a CGImage to a CVPixelBuffer of the given dimensions.
    private func resizeToPixelBuffer(_ image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    // MARK: - Output Helpers

    /// Find the first MLMultiArray output in the feature provider.
    private func firstMultiArrayOutput(_ provider: MLFeatureProvider) -> MLMultiArray? {
        for name in provider.featureNames {
            if let array = provider.featureValue(for: name)?.multiArrayValue {
                return array
            }
        }
        return nil
    }
}
