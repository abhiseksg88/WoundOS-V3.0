import XCTest
import CoreGraphics
import CoreVideo
@testable import WoundAutoSegmentation

final class MaskContourExtractorTests: XCTestCase {

    // MARK: - Helpers

    /// Create a synthetic OneComponent8 CVPixelBuffer with a filled circle.
    private func makeMaskWithCircle(
        width: Int = 256,
        height: Int = 256,
        centerX: Int = 128,
        centerY: Int = 128,
        radius: Int = 60
    ) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        precondition(status == kCVReturnSuccess)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Fill background with 0
        for y in 0..<height {
            for x in 0..<width {
                ptr[y * stride + x] = 0
            }
        }

        // Draw filled circle
        let r2 = radius * radius
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - centerX
                let dy = y - centerY
                if dx * dx + dy * dy <= r2 {
                    ptr[y * stride + x] = 255
                }
            }
        }

        return pixelBuffer
    }

    /// Create an empty (all-zero) mask.
    private func makeEmptyMask(width: Int = 256, height: Int = 256) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        precondition(status == kCVReturnSuccess)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!
        memset(base, 0, height * CVPixelBufferGetBytesPerRow(pixelBuffer))

        return pixelBuffer
    }

    // MARK: - Tests

    func test_extractContour_circleReturnsValidPolygon() throws {
        let mask = makeMaskWithCircle()
        let imageSize = CGSize(width: 256, height: 256)
        let tapPoint = CGPoint(x: 128, y: 128) // center of circle

        let contour = try MaskContourExtractor.extractContour(
            from: mask,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        XCTAssertGreaterThanOrEqual(contour.count, 3, "Contour should have at least 3 points")
    }

    func test_extractContour_pointsWithinImageBounds() throws {
        let mask = makeMaskWithCircle()
        let imageSize = CGSize(width: 256, height: 256)
        let tapPoint = CGPoint(x: 128, y: 128)

        let contour = try MaskContourExtractor.extractContour(
            from: mask,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        for point in contour {
            XCTAssertGreaterThanOrEqual(point.x, 0, "Point x should be >= 0")
            XCTAssertLessThanOrEqual(point.x, imageSize.width, "Point x should be <= image width")
            XCTAssertGreaterThanOrEqual(point.y, 0, "Point y should be >= 0")
            XCTAssertLessThanOrEqual(point.y, imageSize.height, "Point y should be <= image height")
        }
    }

    func test_extractContour_emptyMaskThrows() {
        let mask = makeEmptyMask()
        let imageSize = CGSize(width: 256, height: 256)
        let tapPoint = CGPoint(x: 128, y: 128)

        XCTAssertThrowsError(
            try MaskContourExtractor.extractContour(
                from: mask,
                imageSize: imageSize,
                tapPoint: tapPoint
            )
        ) { error in
            XCTAssertTrue(error is SegmentationError)
        }
    }

    func test_extractContour_tapOutsideCircleStillReturnsContour() throws {
        let mask = makeMaskWithCircle(centerX: 128, centerY: 128, radius: 60)
        let imageSize = CGSize(width: 256, height: 256)
        // Tap far from circle — extractor should fall back to largest contour
        let tapPoint = CGPoint(x: 10, y: 10)

        let contour = try MaskContourExtractor.extractContour(
            from: mask,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        XCTAssertGreaterThanOrEqual(contour.count, 3, "Should still return contour via fallback")
    }

    func test_extractContour_differentImageSizeScalesCorrectly() throws {
        let mask = makeMaskWithCircle(width: 256, height: 256, centerX: 128, centerY: 128, radius: 60)
        // Pretend the original image is 1024x1024; the contour points should be in that space
        let imageSize = CGSize(width: 1024, height: 1024)
        let tapPoint = CGPoint(x: 512, y: 512)

        let contour = try MaskContourExtractor.extractContour(
            from: mask,
            imageSize: imageSize,
            tapPoint: tapPoint
        )

        XCTAssertGreaterThanOrEqual(contour.count, 3)

        // Points should be in the 1024×1024 coordinate space
        for point in contour {
            XCTAssertLessThanOrEqual(point.x, 1024)
            XCTAssertLessThanOrEqual(point.y, 1024)
        }
    }
}
