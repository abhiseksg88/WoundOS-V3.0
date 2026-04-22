import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

#if canImport(UIKit)
import UIKit
#endif

// MARK: - WoundAmbit FUSegNet Segmenter

/// Wound-specific segmenter backed by a CoreML-converted FUSegNet model
/// (EfficientNet-B7 encoder + U-Net decoder with P-scSE attention).
///
/// Pipeline:
///  1. Load `FUSegNet.mlpackage` from the SPM bundle at init.
///  2. Resize input `CGImage` to 512×512.
///  3. Run CoreML prediction → single-channel sigmoid output.
///  4. Threshold at 0.5 → binary mask.
///  5. Sample mask at tap point; if background, use the largest foreground region.
///  6. Convert binary mask to `CVPixelBuffer`.
///  7. Extract contour via shared `MaskContourExtractor`.
///  8. Simplify with `ContourSimplifier`.
///  9. Return `SegmentationResult`.
///
/// Falls back gracefully: if the model file is missing or corrupt, `init()`
/// throws `.modelLoadFailed` and `DependencyContainer` falls through to
/// `VisionForegroundSegmenter`.
public final class WoundAmbitSegmenter: WoundSegmenter {

    public static let modelIdentifier = "woundambit.fusegnet.v1"

    /// Model input resolution (width and height).
    private static let inputSize = 512

    /// Sigmoid threshold for binary mask generation.
    private static let maskThreshold: Float = 0.5

    private let model: MLModel

    /// Initialize by loading the FUSegNet CoreML model from the bundle.
    /// Searches the SPM module bundle first, then the main app bundle.
    /// Throws `SegmentationError.modelLoadFailed` if the model is missing or corrupt.
    public init() throws {
        guard let modelURL = Self.findModelURL() else {
            throw SegmentationError.modelLoadFailed
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Use Neural Engine when available
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            throw SegmentationError.modelLoadFailed
        }
    }

    /// Search for the FUSegNet model across known bundle locations.
    /// Looks for both compiled (.mlmodelc) and source (.mlpackage) formats.
    private static func findModelURL() -> URL? {
        let extensions = ["mlmodelc", "mlpackage"]
        let bundles = [Bundle.main, Bundle(for: WoundAmbitSegmenter.self)]

        for bundle in bundles {
            for ext in extensions {
                if let url = bundle.url(forResource: "FUSegNet", withExtension: ext) {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - WoundSegmenter Conformance

    public func segment(
        image: CGImage,
        tapPoint: CGPoint
    ) async throws -> SegmentationResult {
        let imageSize = CGSize(width: image.width, height: image.height)

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
            prediction = try model.prediction(from: input)
        } catch {
            throw SegmentationError.predictionFailed
        }

        // 3. Extract sigmoid output mask
        guard let outputArray = prediction.featureValue(
            for: "output"
        )?.multiArrayValue ?? firstMultiArrayOutput(prediction) else {
            throw SegmentationError.predictionFailed
        }

        // 4. Threshold to binary mask and convert to CVPixelBuffer
        let maskBuffer = try thresholdToMask(
            outputArray,
            width: Self.inputSize,
            height: Self.inputSize
        )

        // 5. Check if tap point hits foreground in the mask
        let scaledTap = CGPoint(
            x: tapPoint.x / imageSize.width * CGFloat(Self.inputSize),
            y: tapPoint.y / imageSize.height * CGFloat(Self.inputSize)
        )
        let tapHitsForeground = checkTapHitsForeground(
            maskBuffer: maskBuffer,
            tapPoint: scaledTap,
            width: Self.inputSize,
            height: Self.inputSize
        )

        if !tapHitsForeground {
            // Check if there's any foreground at all
            let hasForeground = maskHasForeground(maskBuffer, width: Self.inputSize, height: Self.inputSize)
            if !hasForeground {
                throw SegmentationError.noForegroundDetected
            }
            // There's foreground but tap missed — proceed with largest region
        }

        // 6. Extract contour via shared extractor (maps back to original image size)
        let contour = try MaskContourExtractor.extractContour(
            from: maskBuffer,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        // 7. Simplify
        let simplified = ContourSimplifier.simplify(contour)

        guard simplified.count >= 3 else {
            throw SegmentationError.contourExtractionFailed
        }

        // 8. Compute confidence as mean sigmoid probability over the mask
        let confidence = meanMaskConfidence(outputArray, width: Self.inputSize, height: Self.inputSize)

        return SegmentationResult(
            polygonImageSpace: simplified,
            imageSize: imageSize,
            confidence: confidence,
            modelIdentifier: Self.modelIdentifier
        )
    }

    // MARK: - Image Preprocessing

    /// Resize a CGImage to a CVPixelBuffer of the given dimensions.
    /// Uses CoreGraphics for fast CPU-side resize with bilinear interpolation.
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

    // MARK: - Mask Processing

    /// Threshold the sigmoid output to a binary OneComponent8 mask CVPixelBuffer.
    private func thresholdToMask(
        _ multiArray: MLMultiArray,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
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

        let dataPtr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let totalPixels = width * height

        // Handle both [1, 1, H, W] and [1, H, W] layouts
        let shape = multiArray.shape.map { $0.intValue }
        let spatialOffset: Int
        if shape.count == 4 {
            // [batch, channels, height, width]
            spatialOffset = 0
        } else {
            spatialOffset = 0
        }

        for y in 0..<height {
            for x in 0..<width {
                let idx = spatialOffset + y * width + x
                guard idx < totalPixels else { continue }
                let value = dataPtr[idx]
                let pixel = value >= Self.maskThreshold ? UInt8(255) : UInt8(0)
                ptr[y * stride + x] = pixel
            }
        }

        return buffer
    }

    /// Check if the tap point hits foreground in the binary mask.
    private func checkTapHitsForeground(
        maskBuffer: CVPixelBuffer,
        tapPoint: CGPoint,
        width: Int,
        height: Int
    ) -> Bool {
        let x = min(width - 1, max(0, Int(tapPoint.x)))
        let y = min(height - 1, max(0, Int(tapPoint.y)))

        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(maskBuffer) else { return false }
        let stride = CVPixelBufferGetBytesPerRow(maskBuffer)
        let ptr = base.advanced(by: y * stride + x).assumingMemoryBound(to: UInt8.self)
        return ptr.pointee > 0
    }

    /// Check if the mask has any foreground pixels.
    private func maskHasForeground(_ buffer: CVPixelBuffer, width: Int, height: Int) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let stride = CVPixelBufferGetBytesPerRow(buffer)

        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width where row[x] > 0 {
                return true
            }
        }
        return false
    }

    /// Compute mean sigmoid confidence over foreground pixels.
    private func meanMaskConfidence(_ multiArray: MLMultiArray, width: Int, height: Int) -> Float {
        let dataPtr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let totalPixels = width * height
        var sum: Float = 0
        var count: Int = 0

        for i in 0..<totalPixels {
            let value = dataPtr[i]
            if value >= Self.maskThreshold {
                sum += value
                count += 1
            }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    // MARK: - Output Helpers

    /// Find the first MLMultiArray output in the feature provider.
    /// CoreML models may name their output differently; this is a fallback.
    private func firstMultiArrayOutput(_ provider: MLFeatureProvider) -> MLMultiArray? {
        for name in provider.featureNames {
            if let array = provider.featureValue(for: name)?.multiArrayValue {
                return array
            }
        }
        return nil
    }
}
