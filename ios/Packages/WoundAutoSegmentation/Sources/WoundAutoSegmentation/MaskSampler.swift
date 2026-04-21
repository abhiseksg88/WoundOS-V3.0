import CoreVideo
import Foundation

// MARK: - Mask Sampler

/// Raw access into a `CVPixelBuffer` single-channel UInt8 mask.
///
/// Provides `sampleBit(at:)` for checking whether a pixel is foreground.
/// Instance-level selection is no longer needed — contour extraction
/// handles tap-proximity selection (Bug 2 fix).
///
/// Kept free of Vision imports so it is trivially unit-testable on any
/// `CVPixelBuffer` — including synthetic buffers built in tests.
public enum MaskSampler {

    /// Returns the UInt8 value at the given normalized (0...1) coordinates.
    /// Input is top-left origin (image-space). Returns `nil` if the buffer
    /// can't be locked or coords are out of range.
    public static func sampleBit(
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
}
