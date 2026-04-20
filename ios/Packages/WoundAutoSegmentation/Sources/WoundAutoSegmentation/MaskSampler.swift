import CoreVideo
import Foundation

// MARK: - Mask Sampler

/// Raw access into a `CVPixelBuffer` single-channel UInt8 mask.
///
/// Used by `VisionForegroundSegmenter` to:
///   * sample the multi-class instance mask at the nurse's tap point,
///   * measure each instance's area when the tap misses and we have to
///     fall back to "largest object".
///
/// Kept free of Vision imports so it is trivially unit-testable on any
/// `CVPixelBuffer` — including synthetic buffers built in tests.
public enum MaskSampler {

    /// Returns the instance index at the given normalized (0...1) coordinates.
    /// Input is top-left origin (image-space). Returns `nil` if the buffer
    /// can't be locked or coords are out of range.
    public static func instanceIndexAt(
        buffer: CVPixelBuffer,
        normalizedX: CGFloat,
        normalizedY: CGFloat
    ) -> UInt8? {
        guard (0...1).contains(normalizedX), (0...1).contains(normalizedY) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let x = min(width - 1, max(0, Int(normalizedX * CGFloat(width))))
        let y = min(height - 1, max(0, Int(normalizedY * CGFloat(height))))

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.advanced(by: y * stride + x).assumingMemoryBound(to: UInt8.self)
        return ptr.pointee
    }

    /// Counts pixels equal to `instanceIndex` across the buffer. O(width × height).
    public static func area(buffer: CVPixelBuffer, instanceIndex: UInt8) -> Int {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let stride = CVPixelBufferGetBytesPerRow(buffer)

        var count = 0
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width where row[x] == instanceIndex {
                count += 1
            }
        }
        return count
    }
}
