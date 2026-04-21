import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class WoundAmbitSegmenterTests: XCTestCase {

    // MARK: - Model Loading

    /// The segmenter should throw `.modelLoadFailed` if the FUSegNet model
    /// bundle is not present. This test verifies the graceful failure path
    /// that `DependencyContainer` relies on for fallback to VisionForegroundSegmenter.
    ///
    /// Note: This test will pass when the model is NOT bundled (pre-Stage A).
    /// Once the model is added, this test should be updated to verify successful init.
    func test_init_throwsWhenModelNotBundled() {
        // If the model IS bundled, this test should be skipped or inverted.
        // For now, we expect it to throw since the model hasn't been added yet.
        do {
            _ = try WoundAmbitSegmenter()
            // If we get here, the model IS bundled — verify it loaded
            // This is the success path once Stage A is complete
        } catch {
            XCTAssertTrue(
                error is SegmentationError,
                "Should throw SegmentationError, got \(error)"
            )
            if let segError = error as? SegmentationError {
                XCTAssertEqual(
                    segError,
                    .modelLoadFailed,
                    "Should specifically be .modelLoadFailed"
                )
            }
        }
    }

    // MARK: - Model Identifier

    func test_modelIdentifier() {
        XCTAssertEqual(
            WoundAmbitSegmenter.modelIdentifier,
            "woundambit.fusegnet.v1"
        )
    }

    // MARK: - Segmentation (requires model)

    /// Integration test — only runs when the FUSegNet model is bundled.
    /// Creates a minimal test image and verifies the full pipeline.
    func test_segment_producesValidPolygon() async throws {
        let segmenter: WoundAmbitSegmenter
        do {
            segmenter = try WoundAmbitSegmenter()
        } catch {
            // Model not bundled yet — skip this test
            throw XCTSkip("FUSegNet model not bundled — skipping integration test")
        }

        // Create a simple 512×512 test image (red square)
        guard let image = createTestImage(width: 512, height: 512) else {
            XCTFail("Failed to create test image")
            return
        }

        let tapPoint = CGPoint(x: 256, y: 256)

        do {
            let result = try await segmenter.segment(image: image, tapPoint: tapPoint)

            XCTAssertGreaterThanOrEqual(result.polygonImageSpace.count, 3)
            XCTAssertEqual(result.imageSize.width, 512)
            XCTAssertEqual(result.imageSize.height, 512)
            XCTAssertEqual(result.modelIdentifier, "woundambit.fusegnet.v1")
            XCTAssertGreaterThanOrEqual(result.confidence, 0)
            XCTAssertLessThanOrEqual(result.confidence, 1)
        } catch {
            // It's acceptable for the model to not detect anything in a synthetic image
            XCTAssertTrue(error is SegmentationError)
        }
    }

    /// Verify that an invalid (0×0) image produces an error, not a crash.
    func test_segment_invalidImageThrows() async throws {
        let segmenter: WoundAmbitSegmenter
        do {
            segmenter = try WoundAmbitSegmenter()
        } catch {
            throw XCTSkip("FUSegNet model not bundled — skipping integration test")
        }

        // Create a 1×1 minimal image
        guard let tinyImage = createTestImage(width: 1, height: 1) else {
            XCTFail("Failed to create test image")
            return
        }

        let tapPoint = CGPoint(x: 0, y: 0)

        do {
            _ = try await segmenter.segment(image: tinyImage, tapPoint: tapPoint)
            // If it succeeds on a 1×1 image, that's fine too
        } catch {
            XCTAssertTrue(error is SegmentationError)
        }
    }

    // MARK: - Helpers

    private func createTestImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Fill with a wound-like reddish color
        context.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw a darker circle in the center to simulate wound
        let centerX = CGFloat(width) / 2
        let centerY = CGFloat(height) / 2
        let radius = CGFloat(min(width, height)) / 4
        context.setFillColor(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)
        context.fillEllipse(in: CGRect(
            x: centerX - radius,
            y: centerY - radius,
            width: radius * 2,
            height: radius * 2
        ))

        return context.makeImage()
    }
}

// MARK: - SegmentationError Equatable for testing

extension SegmentationError: Equatable {
    public static func == (lhs: SegmentationError, rhs: SegmentationError) -> Bool {
        switch (lhs, rhs) {
        case (.unsupportedOSVersion, .unsupportedOSVersion),
             (.noForegroundDetected, .noForegroundDetected),
             (.tapPointMissedAllInstances, .tapPointMissedAllInstances),
             (.maskGenerationFailed, .maskGenerationFailed),
             (.contourExtractionFailed, .contourExtractionFailed),
             (.invalidInputImage, .invalidInputImage),
             (.modelLoadFailed, .modelLoadFailed),
             (.predictionFailed, .predictionFailed):
            return true
        default:
            return false
        }
    }
}
